#!/bin/bash

function install {
    local -a skipped_scripts=(
        "acme.sh"
        "entrypoint.sh"
        "functions.sh"
        "install_scripts.sh"
        "start.sh"
    )
    for script_path in /app/*.sh; do
        local script_name
        script_name="$(basename "${script_path}")"

        for skipped_script in "${skipped_scripts[@]}"; do
            if [[ "${script_name}" == "${skipped_script}" ]]; then
                echo "Skipping script: ${script_path}"
                continue 2
            fi
        done

        local usr_local_bin="/usr/local/bin/${script_name%.sh}"
        ln -v -s "${script_path}" "${usr_local_bin}"
        ## Create a symlink without the .sh extension in /app for backwards compatibility with the older docs.
        ln -v -s "${script_path}" "${script_path%.sh}"
    done
}

install
