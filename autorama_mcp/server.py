"""
Autorama MCP Server
Exposes Pixelorama/Autorama tools via MCP protocol.
Forwards all tool calls to the Godot HTTP API server at localhost:7777.

Usage:
  python -m autorama_mcp.server

Configure in Claude Desktop (~/Library/Application Support/Claude/claude_desktop_config.json):
  {
    "mcpServers": {
      "autorama": {
        "command": "python",
        "args": ["-m", "autorama_mcp.server"],
        "cwd": "/Volumes/Data/Autorama-Pixelorama"
      }
    }
  }
"""

from __future__ import annotations

import asyncio
import json
from typing import Any

import httpx
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool

GODOT_URL = "http://127.0.0.1:7777"
TIMEOUT = 30.0

TOOLS: list[Tool] = [
    Tool(
        name="create_canvas",
        description="Create a new sprite canvas in Pixelorama",
        inputSchema={
            "type": "object",
            "properties": {
                "width":  {"type": "integer", "description": "Canvas width in pixels"},
                "height": {"type": "integer", "description": "Canvas height in pixels"},
                "name":   {"type": "string",  "description": "Project name"},
            },
            "required": ["width", "height"],
        },
    ),
    Tool(
        name="get_project_info",
        description="Get info about the current project (size, frame count, layer count)",
        inputSchema={"type": "object", "properties": {}},
    ),
    Tool(
        name="add_layer",
        description="Add a new pixel layer to the current project",
        inputSchema={
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "type": {"type": "integer", "description": "0=pixel layer (default)"},
            },
        },
    ),
    Tool(
        name="add_frame",
        description="Add a new animation frame. Frame 0 exists by default; call this before drawing on frame 1, 2, etc.",
        inputSchema={
            "type": "object",
            "properties": {
                "after_frame": {"type": "integer", "description": "Insert after this frame index"},
            },
        },
    ),
    Tool(
        name="set_frame_duration",
        description="Set the duration of an animation frame in seconds",
        inputSchema={
            "type": "object",
            "properties": {
                "frame":    {"type": "integer"},
                "duration": {"type": "number", "description": "Duration in seconds"},
            },
            "required": ["frame", "duration"],
        },
    ),
    Tool(
        name="fill_area",
        description="Fill a rectangular region with a solid color",
        inputSchema={
            "type": "object",
            "properties": {
                "x":      {"type": "integer"},
                "y":      {"type": "integer"},
                "width":  {"type": "integer"},
                "height": {"type": "integer"},
                "color":  {"type": "string", "description": "Hex color e.g. #FF0000"},
                "frame":  {"type": "integer", "default": 0},
                "layer":  {"type": "integer", "default": 0},
            },
            "required": ["x", "y", "width", "height", "color"],
        },
    ),
    Tool(
        name="draw_pixels",
        description="Draw individual pixels. Each pixel is [x, y, '#RRGGBB'].",
        inputSchema={
            "type": "object",
            "properties": {
                "pixels": {
                    "type": "array",
                    "description": "List of [x, y, '#RRGGBB'] triples",
                    "items": {"type": "array"},
                },
                "frame": {"type": "integer", "default": 0},
                "layer": {"type": "integer", "default": 0},
            },
            "required": ["pixels"],
        },
    ),
    Tool(
        name="get_pixels",
        description="Read all non-transparent pixels from a frame/layer. Returns list of [x, y, '#RRGGBBAA'].",
        inputSchema={
            "type": "object",
            "properties": {
                "frame": {"type": "integer", "default": 0},
                "layer": {"type": "integer", "default": 0},
            },
        },
    ),
    Tool(
        name="export_sprite",
        description="Export the current sprite frame as a PNG file",
        inputSchema={
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute file path for the PNG"},
            },
            "required": ["path"],
        },
    ),
]

app = Server("autorama-pixelorama")


@app.list_tools()
async def list_tools() -> list[Tool]:
    return TOOLS


@app.call_tool()
async def call_tool(name: str, arguments: dict[str, Any]) -> list[TextContent]:
    payload = {"tool": name, "args": arguments}
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            response = await client.post(
                GODOT_URL,
                json=payload,
                headers={"Content-Type": "application/json"},
            )
            response.raise_for_status()
            result = response.json()
    except httpx.ConnectError:
        result = {
            "ok": False,
            "data": (
                f"Cannot connect to Godot at {GODOT_URL}. "
                "Make sure Autorama/Pixelorama is running with the extension loaded."
            ),
        }
    except httpx.TimeoutException:
        result = {"ok": False, "data": f"Request timed out after {TIMEOUT}s"}
    except httpx.HTTPStatusError as exc:
        result = {"ok": False, "data": f"HTTP {exc.response.status_code}: {exc.response.text}"}
    except Exception as exc:
        result = {"ok": False, "data": f"Unexpected error: {exc}"}

    return [TextContent(type="text", text=json.dumps(result, ensure_ascii=False))]


async def main() -> None:
    async with stdio_server() as (read_stream, write_stream):
        await app.run(
            read_stream,
            write_stream,
            app.create_initialization_options(),
        )


if __name__ == "__main__":
    asyncio.run(main())
