#!/usr/bin/env python3
"""
Dynamic inventory for Ansible — reads Terraform output from
deployments/terraform/cloud-demo/.

Usage:
  ansible-playbook -i inventories/terraform_inventory.py ...

Requires: terraform output -json must be run from the cloud-demo directory.
"""

import json
import subprocess
import sys
import os

TERRAFORM_DIR = os.path.join(
    os.path.dirname(__file__), "../../deployments/terraform/cloud-demo"
)


def get_terraform_outputs():
    result = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=os.path.abspath(TERRAFORM_DIR),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Error running terraform output: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def build_inventory(outputs):
    app_ip = outputs["app_public_ip"]["value"]
    k6_ip = outputs["k6_public_ip"]["value"]
    api_url = outputs["api_url"]["value"]

    inventory = {
        "all": {
            "vars": {
                "ansible_user": "ubuntu",
                "ansible_ssh_private_key_file": "~/.ssh/id_rsa",
                "ansible_ssh_common_args": "-o StrictHostKeyChecking=no",
            }
        },
        "app_servers": {
            "hosts": {
                "app_server": {
                    "ansible_host": app_ip,
                    "api_url": api_url,
                    "grafana_url": f"http://{app_ip}:3000",
                    "prometheus_url": f"http://{app_ip}:9090",
                }
            }
        },
        "k6_runners": {
            "hosts": {
                "k6_runner": {
                    "ansible_host": k6_ip,
                    "app_base_url": api_url,
                }
            }
        },
        "_meta": {
            "hostvars": {
                "app_server": {
                    "ansible_host": app_ip,
                    "api_url": api_url,
                    "grafana_url": f"http://{app_ip}:3000",
                    "prometheus_url": f"http://{app_ip}:9090",
                },
                "k6_runner": {
                    "ansible_host": k6_ip,
                    "app_base_url": api_url,
                },
            }
        },
    }
    return inventory


if __name__ == "__main__":
    outputs = get_terraform_outputs()
    inventory = build_inventory(outputs)
    print(json.dumps(inventory, indent=2))
