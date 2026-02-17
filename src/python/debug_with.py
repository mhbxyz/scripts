#!/usr/bin/env python3
import argparse
import asyncio
import re
import sys
from datetime import datetime

from playwright.async_api import async_playwright

__version__ = "1.0.0"

BROWSER_MAP = {
    "chromium": "chromium",
    "chrome": "chromium",
    "firefox": "firefox",
    "webkit": "webkit",
    "safari": "webkit",
}


def log(message):
    time_str = datetime.now().strftime("%H:%M:%S")
    print(f"[{time_str}] {message}")


async def run(browser_name, url, regex_pattern):
    # Compile regex before launching the browser
    try:
        pattern = re.compile(regex_pattern)
    except re.error as e:
        log(f"❌ Regex error: {e}")
        sys.exit(1)

    # Validate URL
    if not url.startswith(("http://", "https://")):
        log("❌ URL must start with http:// or https://")
        sys.exit(1)

    async with async_playwright() as p:
        browser_type = getattr(p, BROWSER_MAP[browser_name])

        log(f"🚀 Launching {browser_name} on {url}")
        log(f"🔍 Active filter (regex): '{regex_pattern}'")
        log("Press Ctrl+C to stop.")

        browser = await browser_type.launch(headless=False)
        context = await browser.new_context()
        page = await context.new_page()

        def on_console(msg):
            if pattern.search(msg.text):
                prefix = {
                    "warning": "⚠️  [WARNING]",
                    "error": "❌ [ERROR]",
                }.get(msg.type, f"[{msg.type.upper()}]")
                print(f"{prefix} {msg.text}")

        page.on("console", on_console)

        try:
            await page.goto(url)
        except Exception as e:
            log(f"❌ Error loading URL: {e}")
            await browser.close()
            sys.exit(1)

        try:
            await asyncio.Future()
        except asyncio.CancelledError:
            pass
        finally:
            await browser.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Open a browser and filter console logs."
    )
    parser.add_argument(
        "browser",
        choices=["chromium", "chrome", "firefox", "webkit", "safari"],
        help="Browser to use",
    )
    parser.add_argument("--at", required=True, help="Target URL")
    parser.add_argument("--filter", required=True, help="Regex to filter logs")
    parser.add_argument(
        "--version", action="version", version=f"%(prog)s {__version__}"
    )

    args = parser.parse_args()

    try:
        asyncio.run(run(args.browser, args.at, args.filter))
    except KeyboardInterrupt:
        log("👋 Stopping.")
        sys.exit(0)
