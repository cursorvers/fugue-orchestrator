/**
 * url-converter.ts
 * Converts X (Twitter) URLs to post text using delegate-grok.js
 */

// Custom error types
export class TimeoutError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TimeoutError";
  }
}

export class RateLimitError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RateLimitError";
  }
}

export class AuthenticationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AuthenticationError";
  }
}

export class InvalidUrlError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidUrlError";
  }
}

/**
 * Converts an X URL to the post text content
 * @param url - X URL in format https://x.com/user/status/{id}
 * @returns Promise<string> - The post text content
 * @throws {InvalidUrlError} - If URL is not a valid X URL
 * @throws {TimeoutError} - If delegate-grok.js times out (30s)
 * @throws {RateLimitError} - If Grok API rate limit is exceeded
 * @throws {AuthenticationError} - If Grok API authentication fails
 */
export async function convertXUrl(url: string): Promise<string> {
  // Validate X URL format
  const xUrlPattern = /^https:\/\/x\.com\/[^\/]+\/status\/\d+/;
  if (!xUrlPattern.test(url)) {
    throw new InvalidUrlError(
      "Invalid X URL. Expected format: https://x.com/user/status/{id}"
    );
  }

  // Prepare task text for delegate-grok.js
  const taskText = `Convert this X URL to post text: ${url}`;

  // Execute delegate-grok.js with timeout
  const command = new Deno.Command("node", {
    args: [
      "/Users/masayuki/.claude/skills/orchestra-delegator/scripts/delegate-grok.js",
      "-a",
      "realtime-info",
      "-t",
      taskText,
    ],
  });

  // Set up timeout (30 seconds)
  const timeoutMs = 30000;
  let timeoutId: number | undefined;
  const timeoutPromise = new Promise<never>((_, reject) => {
    timeoutId = setTimeout(() => {
      reject(
        new TimeoutError(
          "Timeout: delegate-grok.js did not respond within 30 seconds"
        )
      );
    }, timeoutMs);
  });

  try {
    // Race between command execution and timeout
    const output = await Promise.race([command.output(), timeoutPromise]);

    // Clear timeout if command completed successfully
    if (timeoutId !== undefined) {
      clearTimeout(timeoutId);
    }

    // Decode stdout and stderr
    const stdout = new TextDecoder().decode(output.stdout).trim();
    const stderr = new TextDecoder().decode(output.stderr).trim();

    // Handle errors from stderr
    if (!output.success || stderr) {
      // Check for rate limit error (429)
      if (stderr.includes("429")) {
        throw new RateLimitError(
          "Rate limit exceeded. Please try again later."
        );
      }

      // Check for authentication error (401, 403, or "authentication failed")
      if (
        stderr.includes("401") ||
        stderr.includes("403") ||
        stderr.toLowerCase().includes("authentication failed")
      ) {
        throw new AuthenticationError(
          "Authentication failed. Please check your Grok API credentials."
        );
      }

      // Check for timeout error
      if (stderr.toLowerCase().includes("timeout")) {
        throw new TimeoutError(
          "Timeout: delegate-grok.js did not respond within 30 seconds"
        );
      }

      // Generic error
      throw new Error(`delegate-grok.js error: ${stderr}`);
    }

    // Check for invalid URL patterns in Grok response
    const invalidPatterns = [
      /無効な形式/,
      /存在しない投稿/,
      /Invalid URL/i,
      /not found/i,
      /cannot extract/i,
      /提供されたURL/
    ];

    if (invalidPatterns.some(pattern => stdout.match(pattern))) {
      throw new InvalidUrlError("Invalid X/Twitter URL or post not accessible");
    }

    // Return the post text
    return stdout;
  } catch (error) {
    // Clear timeout on error
    if (timeoutId !== undefined) {
      clearTimeout(timeoutId);
    }

    // Re-throw known error types
    if (
      error instanceof TimeoutError ||
      error instanceof RateLimitError ||
      error instanceof AuthenticationError ||
      error instanceof InvalidUrlError
    ) {
      throw error;
    }

    // Handle unexpected errors
    throw new Error(`Unexpected error: ${error}`);
  }
}
