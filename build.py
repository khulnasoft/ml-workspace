import argparse
import datetime
import os
import subprocess
from datetime import timezone

import docker
from ml_buildkit import build_utils
from ml_buildkit.helpers import build_docker

REMOTE_IMAGE_PREFIX = "khulnasoft/"
COMPONENT_NAME = "ml-workspace"
FLAG_FLAVOR = "flavor"

parser = argparse.ArgumentParser(add_help=False)
parser.add_argument(
    "--" + FLAG_FLAVOR,
    help="Flavor (full, light, minimal, gpu) used for docker container",
    default="all",
    choices=["all", "full", "light", "minimal", "gpu"],
)

args = build_utils.parse_arguments(argument_parser=parser)

VERSION = str(args.get(build_utils.FLAG_VERSION))
docker_image_prefix = args.get(build_docker.FLAG_DOCKER_IMAGE_PREFIX)

if not docker_image_prefix:
    docker_image_prefix = REMOTE_IMAGE_PREFIX

flavor = str(args[FLAG_FLAVOR]).lower().strip()

flavors = ["minimal", "light", "full", "gpu"] if flavor == "all" else [flavor]

for flavor_to_build in flavors:
    flavor_dir = flavor_to_build + "-flavor"
    if os.path.exists(flavor_dir):
        build_utils.build(flavor_dir, args)

docker_image_name = COMPONENT_NAME
if flavor in ["minimal", "light"]:
    docker_image_name += "-" + flavor

if args[build_utils.FLAG_MAKE]:
    git_rev = "unknown"
    try:
        git_rev = (
            subprocess.check_output(["git", "rev-parse", "--short", "HEAD"])
            .decode("ascii")
            .strip()
        )
    except Exception:
        pass

    build_date = datetime.datetime.now(timezone.utc).isoformat("T") + "Z"

    build_args = (
        f" --build-arg ARG_VCS_REF={git_rev}"
        f" --build-arg ARG_BUILD_DATE={build_date}"
        f" --build-arg ARG_WORKSPACE_FLAVOR={flavor}"
        f" --build-arg ARG_WORKSPACE_VERSION={VERSION}"
    )

    completed_process = build_docker.build_docker_image(
        docker_image_name, version=VERSION, build_args=build_args
    )
    if completed_process.returncode > 0:
        build_utils.exit_process(1)


if args[build_utils.FLAG_TEST]:
    workspace_name = f"workspace-test-{flavor}"
    workspace_port = "8080"
    client = docker.from_env(timeout=300)
    container = client.containers.run(
        f"{docker_image_name}:{VERSION}",
        name=workspace_name,
        environment={
            "WORKSPACE_NAME": workspace_name,
            "WORKSPACE_ACCESS_PORT": workspace_port,
        },
        detach=True,
    )

    container.reload()
    container_ip = container.attrs["NetworkSettings"]["Networks"]["bridge"]["IPAddress"]

    completed_process = build_utils.run(
        f"docker exec --env WORKSPACE_IP={container_ip} {workspace_name} "
        "pytest '/resources/tests'",
        exit_on_error=False,
    )

    container.remove(force=True)
    if completed_process.returncode > 0:
        build_utils.exit_process(1)


if args[build_utils.FLAG_RELEASE]:
    # Bump all versions in some filess
    previous_version = build_utils.get_latest_version()
    if previous_version:
        build_utils.replace_in_files(
            previous_version,
            VERSION,
            file_paths=["./README.md", "./deployment/google-cloud-run/Dockerfile"],
            regex=False,
            exit_on_error=True,
        )

    build_docker.release_docker_image(
        docker_image_name,
        VERSION,
        docker_image_prefix,
    )
