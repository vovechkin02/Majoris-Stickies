/* SPDX-License-Identifier: MIT */
#ifndef STICKIES_STORE_SESSION_LOCK_H
#define STICKIES_STORE_SESSION_LOCK_H

/* Returns a live, exclusive file-lock descriptor or -1 on failure.
 * The caller owns the descriptor until stickies_store_lock_release(). */
int stickies_store_lock_acquire(const char *directory);
void stickies_store_lock_release(int descriptor);

#endif
