/* The store protocol is owned by the application and exchange utility. */
[CCode (cheader_filename = "store-session-lock.h")]
namespace StickiesStoreLock {
    [CCode (cname = "stickies_store_lock_acquire")]
    public extern int acquire (string directory);

    [CCode (cname = "stickies_store_lock_release")]
    public extern void release (int descriptor);
}
