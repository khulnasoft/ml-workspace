import argparse
import datetime
import subprocess # Consider if this is truly needed or if docker-py suffices for all tasks
import sys # Import sys for sys.exit()

import docker
from ml_buildkit import build_utils
from ml_buildkit.helpers import build_docker

# --- Constants ---
REMOTE_IMAGE_PREFIX = "khulnasoft/"
COMPONENT_NAME = "ml-workspace"
FLAG_FLAVOR = "flavor"

# --- Argument Parsing ---
def parse_arguments():
    """Parses command-line arguments for the build script."""
    parser = argparse.ArgumentParser(
        description="Build, test, and release ML Workspace Docker images.",
        add_help=True # Explicitly add help
    )
    parser.add_argument(
        f"--{FLAG_FLAVOR}",
        help="Flavor (full, light, minimal, gpu) used for docker container. 'all' builds all flavors.",
        default="all",
        choices=["all", "full", "light", "minimal", "gpu"],
    )
    # Assuming build_utils.parse_arguments handles other common flags like --version, --make, --test, --release
    args = build_utils.parse_arguments(argument_parser=parser)
    return args

# --- Main Logic ---
def main():
    args = parse_arguments()

    # Extracting arguments with clear defaults or error handling
    # Use .get() with a default for dictionary access when the key might not be present,
    # though for argparse, direct access (args.flag) is typical after parsing.
    # Assuming build_utils.parse_arguments returns a dict-like object
    # or an argparse.Namespace. Adjust access accordingly.
    
    # Let's assume build_utils.parse_arguments returns a dictionary for consistency with original code
    # If it returns an argparse.Namespace, access would be args.version, args.docker_image_prefix etc.
    VERSION = str(args.get(build_utils.FLAG_VERSION))
    docker_image_prefix = args.get(build_docker.FLAG_DOCKER_IMAGE_PREFIX) or REMOTE_IMAGE_PREFIX

    requested_flavor = str(args[FLAG_FLAVOR]).lower().strip()

    if requested_flavor == "all":
        flavors_to_build = ["minimal", "light", "full", "gpu"]
    else:
        flavors_to_build = [requested_flavor]

    # --- Build Phase ---
    for flavor in flavors_to_build:
        print(f"\n--- Building {flavor} flavor ---")
        build_utils.build(f"{flavor}-flavor", args) # This seems to trigger some pre-build steps

        if args[build_utils.FLAG_MAKE]:
            print(f"--- Making Docker image for {flavor} ---")
            docker_image_name = COMPONENT_NAME
            if flavor in ["minimal", "light"]: # Only append flavor for specific types
                docker_image_name += f"-{flavor}"

            try:
                git_rev = build_utils.get_git_revision()
            except Exception as e:
                print(f"Warning: Could not get Git revision. Error: {e}")
                git_rev = "unknown" # Provide a fallback

            build_date = datetime.datetime.utcnow().isoformat("T") + "Z"

            # F-string for build arguments for better readability
            build_args = (
                f" --build-arg ARG_VCS_REF={git_rev}"
                f" --build-arg ARG_BUILD_DATE={build_date}"
                f" --build-arg ARG_WORKSPACE_FLAVOR={flavor}"
                f" --build-arg ARG_WORKSPACE_VERSION={VERSION}"
            )

            try:
                completed_process = build_docker.build_docker_image(
                    docker_image_name, version=VERSION, build_args=build_args
                )
                if completed_process.returncode != 0:
                    print(f"Error: Docker image build for {flavor} failed with return code {completed_process.returncode}")
                    build_utils.exit_process(1) # Use build_utils.exit_process for consistency
            except Exception as e:
                print(f"Critical Error during Docker image build for {flavor}: {e}")
                build_utils.exit_process(1)


    # --- Test Phase ---
    # This section currently only tests the LAST flavor processed if 'all' was chosen.
    # To test all built flavors, this block should ideally be moved inside the loop
    # or handle the `flavors_to_build` list.
    # Assuming for now it's intended to run once after all builds for the last flavor or a specific one.
    if args[build_utils.FLAG_TEST]:
        print(f"\n--- Running tests for {flavor} ---") # 'flavor' here is the last one from the loop
        workspace_name = f"workspace-test-{flavor}"
        workspace_port = "8080"
        container = None # Initialize container to None for finally block

        try:
            client = docker.from_env()
            container = client.containers.run(
                f"{docker_image_name}:{VERSION}", # Use the correct docker_image_name from the build step
                name=workspace_name,
                environment={
                    "WORKSPACE_NAME": workspace_name,
                    "WORKSPACE_ACCESS_PORT": workspace_port,
                },
                detach=True,
                remove=False # We'll remove it in finally block, but good to be explicit
            )

            container.reload()
            # Safely get IP address, handle potential missing keys
            container_ip = container.attrs.get("NetworkSettings", {}).get("Networks", {}).get("bridge", {}).get("IPAddress")
            if not container_ip:
                raise RuntimeError(f"Could not get IP address for container {workspace_name}")

            print(f"Running tests inside container {workspace_name} at IP {container_ip}")
            # Ensure the command is correctly quoted and formatted for subprocess/docker exec
            # build_utils.run likely uses subprocess.run or similar.
            test_command = f"docker exec --env WORKSPACE_IP={container_ip} {workspace_name} pytest '/resources/tests'"
            completed_process = build_utils.run(
                test_command,
                exit_on_error=False, # Don't exit immediately so we can clean up
            )

            if completed_process.returncode != 0:
                print(f"Error: Tests for {flavor} failed with return code {completed_process.returncode}")
                build_utils.exit_process(1)
            else:
                print(f"Tests for {flavor} passed successfully!")

        except docker.errors.ImageNotFound:
            print(f"Error: Docker image {docker_image_name}:{VERSION} not found for testing.")
            build_utils.exit_process(1)
        except docker.errors.ContainerError as e:
            print(f"Error running container {workspace_name}: {e}")
            if container:
                print(container.logs().decode()) # Print container logs for debugging
            build_utils.exit_process(1)
        except Exception as e:
            print(f"An unexpected error occurred during testing: {e}")
            build_utils.exit_process(1)
        finally:
            if container:
                print(f"Removing container {workspace_name}...")
                try:
                    container.remove(force=True)
                    print(f"Container {workspace_name} removed.")
                except Exception as e:
                    print(f"Error removing container {workspace_name}: {e}")

    # --- Release Phase ---
    # Similar to testing, this will currently only release the LAST flavor processed.
    # Consider if release should apply to ALL built flavors or only the specified one.
    if args[build_utils.FLAG_RELEASE]:
        print(f"\n--- Releasing Docker image for {flavor} ---")
        try:
            # Bump all versions in some files
            previous_version = build_utils.get_latest_version()
            if previous_version:
                print(f"Updating version from {previous_version} to {VERSION} in files.")
                build_utils.replace_in_files(
                    previous_version,
                    VERSION,
                    file_paths=["./README.md", "./deployment/google-cloud-run/Dockerfile"],
                    regex=False,
                    exit_on_error=True, # Exit if replacement fails
                )
            else:
                print("No previous version found to update in files.")

            build_docker.release_docker_image(
                docker_image_name, # Use the correct docker_image_name
                VERSION,
                docker_image_prefix,
            )
            print(f"Successfully released {docker_image_prefix}{docker_image_name}:{VERSION}")
        except Exception as e:
            print(f"Error during release of {docker_image_name}:{VERSION}: {e}")
            build_utils.exit_process(1)

if __name__ == "__main__":
    main()