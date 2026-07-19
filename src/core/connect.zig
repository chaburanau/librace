const std = @import("std");

pub const Options = struct {
    /// Omitted/null means one connection attempt.
    timeout: ?std.Io.Duration = null,
    retry_interval: std.Io.Duration = std.Io.Duration.fromMilliseconds(200),
};

/// Repeatedly calls `connectOnce` until it succeeds, returns a non-retryable
/// error, or the timeout expires. The timeout includes time spent attempting
/// connections as well as time spent sleeping between attempts.
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
    const retry_interval = positiveDuration(options.retry_interval, std.Io.Duration.fromMilliseconds(200));
    const clock = std.Io.Clock.awake;
    const deadline = std.Io.Clock.Timestamp.fromNow(io, .{
        .raw = timeout,
        .clock = clock,
    });
    var first_attempt = true;

    while (true) {
        if (!first_attempt and deadlineReached(io, deadline)) return error.Timeout;
        first_attempt = false;

        if (connectOnce(context)) |result| {
            return result;
        } else |err| {
            if (!isRetryable(err)) return err;

            const remaining = deadline.durationFromNow(io).raw;
            if (remaining.nanoseconds <= 0) return error.Timeout;

            const sleep_for = minDuration(retry_interval, remaining);
            try std.Io.sleep(io, sleep_for, clock);
        }
    }
}

fn deadlineReached(io: std.Io, deadline: std.Io.Clock.Timestamp) bool {
    const now = std.Io.Clock.Timestamp.now(io, deadline.clock);
    return now.raw.nanoseconds >= deadline.raw.nanoseconds;
}

fn positiveDuration(value: std.Io.Duration, fallback: std.Io.Duration) std.Io.Duration {
    return if (value.nanoseconds > 0) value else fallback;
}

fn minDuration(a: std.Io.Duration, b: std.Io.Duration) std.Io.Duration {
    return if (a.nanoseconds <= b.nanoseconds) a else b;
}

const RetryTestError = error{
    NotReady,
    Fatal,
    Timeout,
    Canceled,
};

const RetryTestContext = struct {
    io: std.Io,
    attempts: usize = 0,
    failures_before_success: usize = 0,
    fatal: bool = false,
    attempt_delay: std.Io.Duration = .zero,
};

fn retryTestConnect(ctx: *RetryTestContext) RetryTestError!u32 {
    ctx.attempts += 1;
    if (ctx.attempt_delay.nanoseconds > 0) {
        try std.Io.sleep(ctx.io, ctx.attempt_delay, .awake);
    }
    if (ctx.fatal) return error.Fatal;
    if (ctx.attempts <= ctx.failures_before_success) return error.NotReady;
    return 42;
}

fn retryTestIsRetryable(err: RetryTestError) bool {
    return err == error.NotReady;
}

test "retry without timeout makes one attempt" {
    var ctx = RetryTestContext{
        .io = std.testing.io,
        .failures_before_success = 1,
    };

    try std.testing.expectError(error.NotReady, retry(
        u32,
        RetryTestError,
        *RetryTestContext,
        std.testing.io,
        &ctx,
        .{},
        retryTestConnect,
        retryTestIsRetryable,
    ));
    try std.testing.expectEqual(@as(usize, 1), ctx.attempts);
}

test "retry succeeds after transient failures" {
    var ctx = RetryTestContext{
        .io = std.testing.io,
        .failures_before_success = 2,
    };

    const result = try retry(
        u32,
        RetryTestError,
        *RetryTestContext,
        std.testing.io,
        &ctx,
        .{
            .timeout = std.Io.Duration.fromSeconds(1),
            .retry_interval = std.Io.Duration.fromMilliseconds(1),
        },
        retryTestConnect,
        retryTestIsRetryable,
    );
    try std.testing.expectEqual(@as(u32, 42), result);
    try std.testing.expectEqual(@as(usize, 3), ctx.attempts);
}

test "retry returns fatal error immediately" {
    var ctx = RetryTestContext{
        .io = std.testing.io,
        .fatal = true,
    };

    try std.testing.expectError(error.Fatal, retry(
        u32,
        RetryTestError,
        *RetryTestContext,
        std.testing.io,
        &ctx,
        .{ .timeout = std.Io.Duration.fromSeconds(1) },
        retryTestConnect,
        retryTestIsRetryable,
    ));
    try std.testing.expectEqual(@as(usize, 1), ctx.attempts);
}

test "retry zero timeout still makes the initial attempt" {
    var ctx = RetryTestContext{
        .io = std.testing.io,
        .failures_before_success = 1,
    };

    try std.testing.expectError(error.Timeout, retry(
        u32,
        RetryTestError,
        *RetryTestContext,
        std.testing.io,
        &ctx,
        .{ .timeout = .zero },
        retryTestConnect,
        retryTestIsRetryable,
    ));
    try std.testing.expectEqual(@as(usize, 1), ctx.attempts);
}

test "retry timeout includes connection attempt time" {
    var ctx = RetryTestContext{
        .io = std.testing.io,
        .failures_before_success = 1,
        .attempt_delay = std.Io.Duration.fromMilliseconds(10),
    };

    try std.testing.expectError(error.Timeout, retry(
        u32,
        RetryTestError,
        *RetryTestContext,
        std.testing.io,
        &ctx,
        .{
            .timeout = std.Io.Duration.fromMilliseconds(1),
            .retry_interval = std.Io.Duration.fromMilliseconds(1),
        },
        retryTestConnect,
        retryTestIsRetryable,
    ));
    try std.testing.expectEqual(@as(usize, 1), ctx.attempts);
}
