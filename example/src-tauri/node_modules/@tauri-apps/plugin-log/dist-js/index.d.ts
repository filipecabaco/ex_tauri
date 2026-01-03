import { type UnlistenFn } from '@tauri-apps/api/event';
export interface LogOptions {
    file?: string;
    line?: number;
    keyValues?: Record<string, string | undefined>;
}
export declare enum LogLevel {
    /**
     * The "trace" level.
     *
     * Designates very low priority, often extremely verbose, information.
     */
    Trace = 1,
    /**
     * The "debug" level.
     *
     * Designates lower priority information.
     */
    Debug = 2,
    /**
     * The "info" level.
     *
     * Designates useful information.
     */
    Info = 3,
    /**
     * The "warn" level.
     *
     * Designates hazardous situations.
     */
    Warn = 4,
    /**
     * The "error" level.
     *
     * Designates very serious errors.
     */
    Error = 5
}
/**
 * Logs a message at the error level.
 *
 * @param message
 *
 * # Examples
 *
 * ```js
 * import { error } from '@tauri-apps/plugin-log';
 *
 * const err_info = "No connection";
 * const port = 22;
 *
 * error(`Error: ${err_info} on port ${port}`);
 * ```
 */
export declare function error(message: string, options?: LogOptions): Promise<void>;
/**
 * Logs a message at the warn level.
 *
 * @param message
 *
 * # Examples
 *
 * ```js
 * import { warn } from '@tauri-apps/plugin-log';
 *
 * const warn_description = "Invalid Input";
 *
 * warn(`Warning! {warn_description}!`);
 * ```
 */
export declare function warn(message: string, options?: LogOptions): Promise<void>;
/**
 * Logs a message at the info level.
 *
 * @param message
 *
 * # Examples
 *
 * ```js
 * import { info } from '@tauri-apps/plugin-log';
 *
 * const conn_info = { port: 40, speed: 3.20 };
 *
 * info(`Connected to port {conn_info.port} at {conn_info.speed} Mb/s`);
 * ```
 */
export declare function info(message: string, options?: LogOptions): Promise<void>;
/**
 * Logs a message at the debug level.
 *
 * @param message
 *
 * # Examples
 *
 * ```js
 * import { debug } from '@tauri-apps/plugin-log';
 *
 * const pos = { x: 3.234, y: -1.223 };
 *
 * debug(`New position: x: {pos.x}, y: {pos.y}`);
 * ```
 */
export declare function debug(message: string, options?: LogOptions): Promise<void>;
/**
 * Logs a message at the trace level.
 *
 * @param message
 *
 * # Examples
 *
 * ```js
 * import { trace } from '@tauri-apps/plugin-log';
 *
 * let pos = { x: 3.234, y: -1.223 };
 *
 * trace(`Position is: x: {pos.x}, y: {pos.y}`);
 * ```
 */
export declare function trace(message: string, options?: LogOptions): Promise<void>;
interface RecordPayload {
    level: LogLevel;
    message: string;
}
type LoggerFn = (fn: RecordPayload) => void;
/**
 * Attaches a listener for the log, and calls the passed function for each log entry.
 * @param fn
 *
 * @returns a function to cancel the listener.
 */
export declare function attachLogger(fn: LoggerFn): Promise<UnlistenFn>;
/**
 * Attaches a listener that writes log entries to the console as they come in.
 *
 * @returns a function to cancel the listener.
 */
export declare function attachConsole(): Promise<UnlistenFn>;
export {};
