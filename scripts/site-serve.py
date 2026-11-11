#!/usr/bin/env python3
"""Serve the site for browser checks without dropping parallel image requests."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class PreviewServer(ThreadingHTTPServer):
    # http.server defaults to five queued connections. A fresh Chromium context
    # eagerly loads more images/fonts than that, producing ERR_CONNECTION_RESET
    # and a misleading downstream img.decode EncodingError (#167).
    request_queue_size = 128


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    directory = Path(__file__).resolve().parents[1] / 'site'
    handler = partial(SimpleHTTPRequestHandler, directory=str(directory))
    with PreviewServer(('127.0.0.1', args.port), handler) as server:
        print(f'Serving {directory} on http://127.0.0.1:{args.port}/', flush=True)
        server.serve_forever()
