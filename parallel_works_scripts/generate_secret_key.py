#!/usr/bin/env python3
"""
Generates a unique Django secret key and assigns it to CERF_SERVER_SECRET_KEY
in /ngencerf-app/ngencerf-server/cerfServer/__.env-docker-prod (default file)

Parameters
----------
env_file : str
    path to the env file to update
    (default: /ngencerf-app/ngencerf-server/cerfServer/__.env-docker-prod)

Returns
-------
int
    process exit code
"""


import argparse
import os
import re
import secrets
import sys
import tempfile
from pathlib import Path
from typing import List

ENV_KEY: str = "CERF_SERVER_SECRET_KEY"


def generate_secret() -> str:
    """
    Generate Django secret

    Parameters
    ----------
    None

    Returns
    -------
    str
        secret key
    """
    # URL-safe token with 50 random bytes
    return secrets.token_urlsafe(50)


def update_env_file(env_path: Path, secret: str) -> None:
    """
    Load an existing environment file, replace any existing
    CERF_SERVER_SECRET_KEY line, or append if missing, then
    writing back to file atomically (to avoid partial writes)

    Parameters
    ----------
    env_path : Path
        path to existing environment file
    secret : str
        secret value to write

    returns
    -------
    None
    """
    # read existing lines or fail if file not found
    try:
        lines: List[str] = env_path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        raise FileNotFoundError(f"env file not found: {env_path}") from None

    # filter out any existing key at start of line
    pattern = re.compile(rf"^{re.escape(ENV_KEY)}=.*$")
    filtered: List[str] = [ln for ln in lines if not pattern.match(ln)]

    # append new key=value
    filtered.append(f"{ENV_KEY}={secret}")

    # atomic write to same directory
    with tempfile.NamedTemporaryFile(
        "w",
        delete=False,
        dir=str(env_path.parent),
        encoding="utf-8"
    ) as tmp:
        tmp.write("\n".join(filtered) + "\n")
        tmp_path: Path = Path(tmp.name)

    os.replace(tmp_path, env_path)


def main(argv: List[str]) -> int:
    """
    CLI entrypoint to update the env file with a new Django secret

    Parameters
    ----------
    argv : List[str]
        command line arguments

    Returns
    -------
    int
        process exit code
    """
    # create argument parser
    parser = argparse.ArgumentParser()

    # add argument
    parser.add_argument(
        "env_file",
        nargs="?",
        default="/ngencerf-app/ngencerf-server/cerfServer/__.env-docker-prod",
        help="path to the env file to update",
    )

    # parse arguments
    args = parser.parse_args(argv)

    # get env file path
    env_path: Path = Path(args.env_file)

    # generate secret
    secret: str = generate_secret()

    # update env file with new secret
    update_env_file(env_path, secret)
    print(f"updated {env_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
