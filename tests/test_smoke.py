# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.
"""Host-side smoke test: run with the snap installed (`tox -e smoke`)."""

import subprocess
import time

import yaml


def _snapcraft():
    with open("snap/snapcraft.yaml") as file:
        return yaml.safe_load(file)


def test_all_apps():
    snapcraft = _snapcraft()
    # mysqladmin --help exits 1 upstream (usage then error status)
    override = {"mysqladmin": "--version"}
    for app, data in snapcraft["apps"].items():
        if not data.get("daemon"):
            arg = override.get(app, "--help")
            print(f"Running {snapcraft['name']}.{app} {arg}...")
            subprocess.check_output(["sudo", f"{snapcraft['name']}.{app}", arg])


def test_all_services():
    snapcraft = _snapcraft()
    for app, data in snapcraft["apps"].items():
        if data.get("daemon"):
            service = f"{snapcraft['name']}.{app}"
            subprocess.check_output(["sudo", "snap", "start", service])
            time.sleep(5)
            status = subprocess.check_output(["snap", "services", service]).decode()
            assert "active" in status


def test_version():
    snapcraft = _snapcraft()
    mysql_version, vsql_version = snapcraft["version"].split("-", 1)
    out = subprocess.check_output(
        ["sudo", f"{snapcraft['name']}.mysql", "-uroot", "-N", "-e", "SELECT VERSION();"]
    ).decode()
    assert out.startswith(f"{mysql_version}-villagesql-{vsql_version}")
