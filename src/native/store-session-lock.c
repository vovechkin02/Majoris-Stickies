/* SPDX-License-Identifier: MIT */
#include "store-session-lock.h"

#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

/* Acquire the shared store protocol's exclusive advisory lifetime lock. */
int
stickies_store_lock_acquire(const char *directory)
{
    struct stat directory_info;
    struct stat lock_info;
    char path[PATH_MAX];
    int descriptor;

    if (directory == NULL || lstat(directory, &directory_info) != 0 ||
        !S_ISDIR(directory_info.st_mode) || directory_info.st_uid != geteuid()) {
        return -1;
    }

    int count = snprintf(path, sizeof(path), "%s/.stickies-session.lock", directory);
    if (count < 0 || (size_t) count >= sizeof(path)) {
        return -1;
    }

    descriptor = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (descriptor < 0) {
        return -1;
    }
    if (fstat(descriptor, &lock_info) != 0 || !S_ISREG(lock_info.st_mode) ||
        lock_info.st_uid != geteuid() || lock_info.st_nlink != 1 ||
        (lock_info.st_mode & 0077) != 0 ||
        flock(descriptor, LOCK_EX | LOCK_NB) != 0) {
        close(descriptor);
        return -1;
    }
    return descriptor;
}

/* Release the descriptor; kernel locking survives only while it is held. */
void
stickies_store_lock_release(int descriptor)
{
    if (descriptor >= 0) {
        close(descriptor);
    }
}
