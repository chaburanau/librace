const std = @import("std");

pub const Options = struct {
    /// Omitted/null means one connection attempt.
    timeout: ?std.Io.Duration = null,
    retry_interval: std.Io.Duration = std.Io.Duration.fromMilliseconds(200),
};

pub fn retry(
    comptime Result: type,
    comptime ConnectError: type,
    comptime Context: type,
    io: std.Io,
    context: Context,
    options: Options,
    comptime connectOnce: fn (Context) ConnectError!Result,
    comptime isRetryable: fn (ConnectError) bool,
) ConnectError!Result {
    const timeout = options.timeout orelse return connectOnce(context);
    const step = positiveDuration(options.retry_interval, std.Io.Duration.fromMilliseconds(200));
    var elapsed = std.Io.Duration.zero;

    while (true) {
        if (connectOnce(context)) |result| {
            return result;
        } else |err| {
            if (!isRetryable(err)) return err;
            if (elapsed.nanoseconds >= timeout.nanoseconds) return error.Timeout;

            const remaining = std.Io.Duration.fromNanoseconds(timeout.nanoseconds - elapsed.nanoseconds);
            const sleep_for = minDuration(step, remaining);
            std.Io.sleep(io, sleep_for, .real) catch {};
            elapsed = std.Io.Duration.fromNanoseconds(elapsed.nanoseconds + sleep_for.nanoseconds);
        }
    }
}

pub fn positiveDuration(value: std.Io.Duration, fallback: std.Io.Duration) std.Io.Duration {
    return if (value.nanoseconds > 0) value else fallback;
}

pub fn minDuration(a: std.Io.Duration, b: std.Io.Duration) std.Io.Duration {
    return if (a.nanoseconds <= b.nanoseconds) a else b;
}
