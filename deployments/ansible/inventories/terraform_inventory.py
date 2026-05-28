#!/usr/bin/env python3
"""
Dynamic inventory for Ansible. Reads Terraform output from:
deployments/terraform/cloud-demo
"""

import json
import os
import subprocess
import sys

TERRAFORM_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "../../terraform/cloud-demo")
)


def get_terraform_outputs():
    result = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=TERRAFORM_DIR,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        print(f"Error running terraform output from {TERRAFORM_DIR}: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def output_value(outputs, name):
    try:
        return outputs[name]["value"]
    except KeyError:
        print(f"Missing Terraform output: {name}", file=sys.stderr)
        sys.exit(1)


def build_inventory(outputs):
    app_ip = output_value(outputs, "app_public_ip")
    k6_ip = output_value(outputs, "k6_public_ip")
    api_url = output_value(outputs, "api_url")

    hostvars = {
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

    return {
        "all": {
            "vars": {
                "ansible_user": "ubuntu",
                "ansible_ssh_private_key_file": os.path.expanduser("~/.ssh/id_rsa"),
                "ansible_ssh_common_args": "-o StrictHostKeyChecking=no",
            }
        },
        "app_servers": {"hosts": {"app_server": hostvars["app_server"]}},
        "k6_runners": {"hosts": {"k6_runner": hostvars["k6_runner"]}},
        "_meta": {"hostvars": hostvars},
    }


if __name__ == "__main__":
    print(json.dumps(build_inventory(get_terraform_outputs()), indent=2))
