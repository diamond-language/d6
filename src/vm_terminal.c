#define _GNU_SOURCE

#include "vm_internal.h"

#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

/* The terminal primitives behind the prelude's STDIN.raw and STDOUT.winsize (the
 * DIAMOND_FILE_PATH_TERMINAL_* selectors, src/vm.h). STDIN.readpartial reads through
 * stdin_read_partial in src/vm_process_io.c, which shares gets' stdin state.
 *
 * Raw mode belongs to the process, not to a VM: there is one terminal. The settings
 * it replaced are kept here and put back when the block that entered it ends, and by
 * an atexit handler when the program exits from inside the block, so a shell is never
 * left without echo. Entering it again while it is on does nothing and reports so,
 * which makes nested STDIN.raw blocks leave the mode to the outermost one. */
static struct {
    pthread_mutex_t lock;
    bool raw;
    bool restore_registered;
    struct termios saved;
} terminal_state={.lock=PTHREAD_MUTEX_INITIALIZER};

static void restore_terminal_at_exit(void) {
    if(terminal_state.raw) {
        (void)tcsetattr(STDIN_FILENO,TCSAFLUSH,&terminal_state.saved);
        terminal_state.raw=false;
    }
}

/* The descriptor for :stdin, :stdout or :stderr (a Symbol or String), or -1. */
static int standard_stream_descriptor(DiamondValue stream) {
    if(stream.kind!=DIAMOND_VALUE_OBJECT||(stream.as.object->kind!=DIAMOND_OBJECT_SYMBOL&&
       stream.as.object->kind!=DIAMOND_OBJECT_STRING))return -1;
    /* A Symbol and a String share their layout (length, then chars). */
    const DiamondString *name=(const DiamondString *)stream.as.object;
    if(name->length==5&&memcmp(name->chars,"stdin",5)==0)return STDIN_FILENO;
    if(name->length==6&&memcmp(name->chars,"stdout",6)==0)return STDOUT_FILENO;
    if(name->length==6&&memcmp(name->chars,"stderr",6)==0)return STDERR_FILENO;
    return -1;
}

/* Raw mode as cfmakeraw sets it: no echo, no line editing, no signal keys (Ctrl-C
 * arrives as byte 3), no CR/NL translation either way, and a read returns as soon as
 * one byte is there. */
static DiamondVmStatus enter_raw_mode(DiamondVm *vm,DiamondValue *result) {
    if(terminal_state.raw) {
        *result=DIAMOND_BOOL(false);
        return DIAMOND_VM_OK;
    }
    if(!isatty(STDIN_FILENO)||tcgetattr(STDIN_FILENO,&terminal_state.saved)!=0) {
        snprintf(vm->error,sizeof vm->error,"STDIN.raw needs a terminal: %s",
            isatty(STDIN_FILENO)?strerror(errno):"STDIN is not one");
        return DIAMOND_VM_IO_ERROR;
    }
#ifdef __wasi__
    /* No terminal to configure (and no termios flags): the same error as a pipe. */
    snprintf(vm->error,sizeof vm->error,"STDIN.raw needs a terminal: STDIN is not one");
    return DIAMOND_VM_IO_ERROR;
#else
    struct termios raw=terminal_state.saved;
    raw.c_iflag&=~(tcflag_t)(IGNBRK|BRKINT|PARMRK|ISTRIP|INLCR|IGNCR|ICRNL|IXON);
    raw.c_oflag&=~(tcflag_t)OPOST;
    raw.c_lflag&=~(tcflag_t)(ECHO|ECHONL|ICANON|ISIG|IEXTEN);
    raw.c_cflag&=~(tcflag_t)(CSIZE|PARENB);
    raw.c_cflag|=CS8;
    raw.c_cc[VMIN]=1;
    raw.c_cc[VTIME]=0;
    if(tcsetattr(STDIN_FILENO,TCSAFLUSH,&raw)!=0) {
        snprintf(vm->error,sizeof vm->error,"STDIN.raw: %s",strerror(errno));
        return DIAMOND_VM_IO_ERROR;
    }
    terminal_state.raw=true;
    if(!terminal_state.restore_registered&&atexit(restore_terminal_at_exit)==0)
        terminal_state.restore_registered=true;
    *result=DIAMOND_BOOL(true);
    return DIAMOND_VM_OK;
#endif
}

static DiamondVmStatus leave_raw_mode(DiamondVm *vm,DiamondValue *result) {
    *result=DIAMOND_BOOL(terminal_state.raw);
    if(!terminal_state.raw)return DIAMOND_VM_OK;
    terminal_state.raw=false;
    if(tcsetattr(STDIN_FILENO,TCSAFLUSH,&terminal_state.saved)!=0) {
        snprintf(vm->error,sizeof vm->error,"STDIN.raw: %s",strerror(errno));
        return DIAMOND_VM_IO_ERROR;
    }
    return DIAMOND_VM_OK;
}

DiamondVmStatus terminal_raw(DiamondVm *vm,DiamondValue stream,DiamondValue on,
        DiamondValue *result) {
    if(standard_stream_descriptor(stream)!=STDIN_FILENO) {
        snprintf(vm->error,sizeof vm->error,"raw mode is set through STDIN");
        return DIAMOND_VM_TYPE_ERROR;
    }
    if(on.kind!=DIAMOND_VALUE_BOOL) {
        snprintf(vm->error,sizeof vm->error,"raw mode takes true or false");
        return DIAMOND_VM_TYPE_ERROR;
    }
    pthread_mutex_lock(&terminal_state.lock);
    const DiamondVmStatus status=on.as.boolean?enter_raw_mode(vm,result):
        leave_raw_mode(vm,result);
    pthread_mutex_unlock(&terminal_state.lock);
    return status;
}

/* [rows, columns] of the terminal the stream writes to or reads from, or nil when it
 * is not a terminal (a pipe, a file) or the platform cannot say. */
DiamondVmStatus terminal_winsize(DiamondVm *vm,DiamondValue stream,DiamondValue *result) {
    const int descriptor=standard_stream_descriptor(stream);
    if(descriptor<0) {
        snprintf(vm->error,sizeof vm->error,"winsize takes :stdin, :stdout or :stderr");
        return DIAMOND_VM_TYPE_ERROR;
    }
    *result=DIAMOND_NIL;
#ifdef TIOCGWINSZ
    struct winsize size={0};
    if(ioctl(descriptor,TIOCGWINSZ,&size)!=0||size.ws_row==0||size.ws_col==0)
        return DIAMOND_VM_OK;
    const DiamondValue values[2]={DIAMOND_INT(size.ws_row),DIAMOND_INT(size.ws_col)};
    DiamondArray *pair=allocate_array(vm,values,2);
    if(pair==nullptr)return DIAMOND_VM_OUT_OF_MEMORY;
    *result=DIAMOND_OBJECT(pair);
#endif
    return DIAMOND_VM_OK;
}
