const std = @import("std");

/// Native Darwin/POSIX Blocking Mutex
pub const Mutex = struct {
    handle: std.c.pthread_mutex_t = .{},

    extern "c" fn pthread_mutex_init(mutex: *std.c.pthread_mutex_t, attr: ?*anyopaque) c_int;
    extern "c" fn pthread_mutex_lock(mutex: *std.c.pthread_mutex_t) c_int;
    extern "c" fn pthread_mutex_unlock(mutex: *std.c.pthread_mutex_t) c_int;
    extern "c" fn pthread_mutex_destroy(mutex: *std.c.pthread_mutex_t) c_int;

    pub fn init() Mutex {
        var self = Mutex{};
        _ = pthread_mutex_init(&self.handle, null);
        return self;
    }

    pub fn deinit(self: *Mutex) void {
        _ = pthread_mutex_destroy(&self.handle);
    }

    pub fn lock(self: *Mutex) void {
        _ = pthread_mutex_lock(&self.handle);
    }

    pub fn unlock(self: *Mutex) void {
        _ = pthread_mutex_unlock(&self.handle);
    }
};

/// Native Darwin/POSIX Condition Variable
pub const Condition = struct {
    handle: std.c.pthread_cond_t = .{},

    extern "c" fn pthread_cond_init(cond: *std.c.pthread_cond_t, attr: ?*anyopaque) c_int;
    extern "c" fn pthread_cond_wait(cond: *std.c.pthread_cond_t, mutex: *std.c.pthread_mutex_t) c_int;
    extern "c" fn pthread_cond_signal(cond: *std.c.pthread_cond_t) c_int;
    extern "c" fn pthread_cond_broadcast(cond: *std.c.pthread_cond_t) c_int;
    extern "c" fn pthread_cond_destroy(cond: *std.c.pthread_cond_t) c_int;

    pub fn init() Condition {
        var self = Condition{};
        _ = pthread_cond_init(&self.handle, null);
        return self;
    }

    pub fn deinit(self: *Condition) void {
        _ = pthread_cond_destroy(&self.handle);
    }

    pub fn wait(self: *Condition, mutex: *Mutex) void {
        _ = pthread_cond_wait(&self.handle, &mutex.handle);
    }

    pub fn signal(self: *Condition) void {
        _ = pthread_cond_signal(&self.handle);
    }

    pub fn broadcast(self: *Condition) void {
        _ = pthread_cond_broadcast(&self.handle);
    }
};

/// Native Darwin/POSIX Blocking Semaphore (Built on top of Mutex/Cond)
pub const Semaphore = struct {
    mutex: Mutex,
    cond: Condition,
    permits: usize,

    pub fn init(initial: usize) Semaphore {
        return .{
            .mutex = Mutex.init(),
            .cond = Condition.init(),
            .permits = initial,
        };
    }

    pub fn deinit(self: *Semaphore) void {
        self.mutex.deinit();
        self.cond.deinit();
    }

    pub fn wait(self: *Semaphore) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        while (self.permits == 0) {
            self.cond.wait(&self.mutex);
        }
        self.permits -= 1;
    }

    pub fn post(self: *Semaphore) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.permits += 1;
        self.cond.signal();
    }

    pub fn postAll(self: *Semaphore) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.permits += 1000;
        self.cond.broadcast();
    }
};
