#!/usr/bin/env bash
#################################################
# Please do not make any changes to this file,  #
# change the variables in webui-user.sh instead #
#################################################

export COMMANDLINE_ARGS=""

use_venv=1
if [[ $venv_dir == "-" ]]; then
  use_venv=0
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# If run from macOS, load defaults from webui-macos-env.sh
if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ -f "$SCRIPT_DIR"/webui-macos-env.sh ]]
        then
        source "$SCRIPT_DIR"/webui-macos-env.sh
    fi
fi

# Read variables from webui-user.sh
# shellcheck source=/dev/null
if [[ -f "$SCRIPT_DIR"/webui-user.sh ]]
then
    source "$SCRIPT_DIR"/webui-user.sh
fi

# Set defaults
# Install directory without trailing slash
if [[ -z "${install_dir}" ]]
then
    install_dir="$SCRIPT_DIR"
fi

# Name of the subdirectory (defaults to stable-diffusion-webui)
if [[ -z "${clone_dir}" ]]
then
    clone_dir="stable-diffusion-webui"
fi

# python3 executable
if [[ -z "${python_cmd}" ]]
then
    python_cmd="python3"
fi

# git executable
if [[ -z "${GIT}" ]]
then
    export GIT="git"
fi

# python3 venv without trailing slash (defaults to ${install_dir}/${clone_dir}/venv)
if [[ -z "${venv_dir}" ]] && [[ $use_venv -eq 1 ]]
then
    venv_dir="venv"
fi

if [[ -z "${LAUNCH_SCRIPT}" ]]
then
    LAUNCH_SCRIPT="launch.py"
fi

# this script cannot be run as root by default
can_run_as_root=0

# read any command line flags to the webui.sh script
while getopts "f" flag > /dev/null 2>&1
do
    case ${flag} in
        f) can_run_as_root=1;;
        *) break;;
    esac
done

# Disable sentry logging
export ERROR_REPORTING=FALSE

# Do not reinstall existing pip packages on Debian/Ubuntu
export PIP_IGNORE_INSTALLED=0

# Pretty print
delimiter="################################################################"

printf "\n%s\n" "${delimiter}"
printf "\e[1m\e[32mInstall script for stable-diffusion + Web UI\n"
printf "\e[1m\e[34mTested on Debian 11 (Bullseye)\e[0m"
printf "\n%s\n" "${delimiter}"

# Do not run as root
if [[ $(id -u) -eq 0 && can_run_as_root -eq 0 ]]
then
    printf "\n%s\n" "${delimiter}"
    printf "\e[1m\e[31mERROR: This script must not be launched as root, aborting...\e[0m"
    printf "\n%s\n" "${delimiter}"
    exit 1
else
    printf "\n%s\n" "${delimiter}"
    printf "Running on \e[1m\e[32m%s\e[0m user" "$(whoami)"
    printf "\n%s\n" "${delimiter}"
fi

if [[ $(getconf LONG_BIT) = 32 ]]
then
    printf "\n%s\n" "${delimiter}"
    printf "\e[1m\e[31mERROR: Unsupported Running on a 32bit OS\e[0m"
    printf "\n%s\n" "${delimiter}"
    exit 1
fi

if [[ -d .git ]]
then
    printf "\n%s\n" "${delimiter}"
    printf "Repo already cloned, using it as install directory"
    printf "\n%s\n" "${delimiter}"
    install_dir="${PWD}/../"
    clone_dir="${PWD##*/}"
fi

# Check prerequisites
gpu_info=$(lspci 2>/dev/null | grep -E "VGA|Display")
case "$gpu_info" in
    *"Navi 1"*)
        export HSA_OVERRIDE_GFX_VERSION=10.3.0
        if [[ -z "${TORCH_COMMAND}" ]]
        then
            pyv="$(${python_cmd} -c 'import sys; print(".".join(map(str, sys.version_info[0:2])))')"
            if [[ $(bc <<< "$pyv <= 3.10") -eq 1 ]] 
            then
                # Navi users will still use torch 1.13 because 2.0 does not seem to work.
                export TORCH_COMMAND="pip install torch==1.13.1+rocm5.2 torchvision==0.14.1+rocm5.2 --index-url https://download.pytorch.org/whl/rocm5.2"
            else
                printf "\e[1m\e[31mERROR: RX 5000 series GPUs must be using at max python 3.10, aborting...\e[0m"
                exit 1
            fi
        fi
    ;;
    *"Navi 2"*) export HSA_OVERRIDE_GFX_VERSION=10.3.0
    ;;
    *"Navi 3"*) [[ -z "${TORCH_COMMAND}" ]] && \
         export TORCH_COMMAND="pip install --pre torch torchvision --index-url https://download.pytorch.org/whl/nightly/rocm5.6"
        # Navi 3 needs at least 5.5 which is only on the nightly chain, previous versions are no longer online (torch==2.1.0.dev-20230614+rocm5.5 torchvision==0.16.0.dev-20230614+rocm5.5 torchaudio==2.1.0.dev-20230614+rocm5.5)
        # so switch to nightly rocm5.6 without explicit versions this time
    ;;
    *"Renoir"*) export HSA_OVERRIDE_GFX_VERSION=9.0.0
        printf "\n%s\n" "${delimiter}"
        printf "Experimental support for Renoir: make sure to have at least 4GB of VRAM and 10GB of RAM or enable cpu mode: --use-cpu all --no-half"
        printf "\n%s\n" "${delimiter}"
    ;;
    *)
    ;;
esac
if ! echo "$gpu_info" | grep -q "NVIDIA";
then
    if echo "$gpu_info" | grep -q "AMD" && [[ -z "${TORCH_COMMAND}" ]]
    then
        export TORCH_COMMAND="pip install torch==2.0.1+rocm5.4.2 torchvision==0.15.2+rocm5.4.2 --index-url https://download.pytorch.org/whl/rocm5.4.2"
    fi
fi

for preq in "${GIT}" "${python_cmd}"
do
    if ! hash "${preq}" &>/dev/null
    then
        printf "\n%s\n" "${delimiter}"
        printf "\e[1m\e[31mERROR: %s is not installed, aborting...\e[0m" "${preq}"
        printf "\n%s\n" "${delimiter}"
        exit 1
    fi
done

if [[ $use_venv -eq 1 ]] && ! "${python_cmd}" -c "import venv" &>/dev/null
then
    printf "\n%s\n" "${delimiter}"
    printf "\e[1m\e[31mERROR: python3-venv is not installed, aborting...\e[0m"
    printf "\n%s\n" "${delimiter}"
    exit 1
fi

cd "${install_dir}"/ || { printf "\e[1m\e[31mERROR: Can't cd to %s/, aborting...\e[0m" "${install_dir}"; exit 1; }
if [[ -d "${clone_dir}" ]]
then
    cd "${clone_dir}"/ || { printf "\e[1m\e[31mERROR: Can't cd to %s/%s/, aborting...\e[0m" "${install_dir}" "${clone_dir}"; exit 1; }
else
    printf "\n%s\n" "${delimiter}"
    printf "Clone stable-diffusion-webui"
    printf "\n%s\n" "${delimiter}"
    "${GIT}" clone https://github.com/AUTOMATIC1111/stable-diffusion-webui "${clone_dir}"
    cd "${clone_dir}"/ || { printf "\e[1m\e[31mERROR: Can't cd to %s/%s/, aborting...\e[0m" "${install_dir}" "${clone_dir}"; exit 1; }
fi


# Function to clone a git repository only if it doesn't already exist
clone_if_not_exists() {
    local repo_url=$1
    local target_dir=$2
    if [ ! -d "$target_dir" ]; then
        git clone "$repo_url" "$target_dir"
    else
        echo "Directory $target_dir already exists, skipping git clone."
    fi
}

# Function to download a file only if it doesn't already exist
download_if_not_exists() {
    local url=$1
    local target_file=$2
    if [ ! -f "$target_file" ]; then
        wget -O "$target_file" "$url" -q --no-verbose
        echo "File $target_file downloaded." 
    else
        echo "File $target_file already exists, skipping download."
    fi
}

# Cloning Extensions
clone_if_not_exists "https://github.com/ranareehanmetex/stable-diffusion-webui-nsfw-filter-metex" "stable-diffusion-webui/extensions/stable-diffusion-webui-nsfw-filter/"
clone_if_not_exists "https://github.com/ranareehanmetex/stable-diffusion-webui-promptgen" "stable-diffusion-webui/extensions/stable-diffusion-webui-promptgen/"
clone_if_not_exists "https://github.com/ranareehanmetex/adetailer" "stable-diffusion-webui/extensions/adetailer/"
clone_if_not_exists "https://github.com/ranareehanmetex/promptgen-metex" "stable-diffusion-webui/promptgen-metex/"

# Downloading most popular CivitAi Models
download_if_not_exists "https://civitai.com/api/download/models/72396" "models/Stable-diffusion/layriel_v16.safetensors"
download_if_not_exists "https://civitai.com/api/download/models/176425" "models/Stable-diffusion/majicmixRealistic_betterV2V25.safetensors"
download_if_not_exists "https://civitai.com/api/download/models/138176" "models/Stable-diffusion/cyberrealistic_v32.safetensors"
download_if_not_exists "https://civitai.com/api/download/models/79290" "models/Stable-diffusion/aZovyaRPGArtistTools_v3.safetensors"
download_if_not_exists "https://civitai.com/api/download/models/64094" "models/Stable-diffusion/neverendingDreamNED_v122BakedVae.safetensors"
download_if_not_exists "https://civitai.com/api/download/models/76907" "models/Stable-diffusion/ghostmix_v20Bakedvae.safetensors"
download_if_not_exists "https://civitai.com/api/download/models/128713" "models/Stable-diffusion/dreamshaper_8.safetensors"
download_if_not_exists "https://civitai.com/api/download/models/119057" "models/Stable-diffusion/meinamix_meinaV11.safetensors"
download_if_not_exists "https://huggingface.co/XpucT/Deliberate/resolve/main/Deliberate_v2.safetensors?download=true" "models/Stable-diffusion/deliberate_v2.safetensors"
download_if_not_exists "https://civitai.com/api/download/models/46846" "models/Stable-diffusion/revAnimated_v122.safetensors"
download_if_not_exists "https://civitai.com/api/download/models/5677" "models/Stable-diffusion/epicDiffusion_epicDiffusion11.safetensors"
download_if_not_exists "https://civitai.com/api/download/models/143906" "models/Stable-diffusion/epicrealism_pureEvolutionV4.safetensors"
download_if_not_exists "https://civitai.com/api/download/models/130072" "models/Stable-diffusion/realisticVisionV51_v51VAE.safetensors"

# Add any additional script actions here




if [[ $use_venv -eq 1 ]] && [[ -z "${VIRTUAL_ENV}" ]];
then
    printf "\n%s\n" "${delimiter}"
    printf "Create and activate python venv"
    printf "\n%s\n" "${delimiter}"
    cd "${install_dir}"/"${clone_dir}"/ || { printf "\e[1m\e[31mERROR: Can't cd to %s/%s/, aborting...\e[0m" "${install_dir}" "${clone_dir}"; exit 1; }
    if [[ ! -d "${venv_dir}" ]]
    then
        "${python_cmd}" -m venv "${venv_dir}"
        first_launch=1
    fi
    # shellcheck source=/dev/null
    if [[ -f "${venv_dir}"/bin/activate ]]
    then
        source "${venv_dir}"/bin/activate
    else
        printf "\n%s\n" "${delimiter}"
        printf "\e[1m\e[31mERROR: Cannot activate python venv, aborting...\e[0m"
        printf "\n%s\n" "${delimiter}"
        exit 1
    fi
else
    printf "\n%s\n" "${delimiter}"
    printf "python venv already activate or run without venv: ${VIRTUAL_ENV}"
    printf "\n%s\n" "${delimiter}"
fi

# Try using TCMalloc on Linux
prepare_tcmalloc() {
    if [[ "${OSTYPE}" == "linux"* ]] && [[ -z "${NO_TCMALLOC}" ]] && [[ -z "${LD_PRELOAD}" ]]; then
        TCMALLOC="$(PATH=/usr/sbin:$PATH ldconfig -p | grep -Po "libtcmalloc(_minimal|)\.so\.\d" | head -n 1)"
        if [[ ! -z "${TCMALLOC}" ]]; then
            echo "Using TCMalloc: ${TCMALLOC}"
            export LD_PRELOAD="${TCMALLOC}"
        else
            printf "\e[1m\e[31mCannot locate TCMalloc (improves CPU memory usage)\e[0m\n"
        fi
    fi
}


KEEP_GOING=1
export SD_WEBUI_RESTART=tmp/restart
while [[ "$KEEP_GOING" -eq "1" ]]; do
    if [[ ! -z "${ACCELERATE}" ]] && [ ${ACCELERATE}="True" ] && [ -x "$(command -v accelerate)" ]; then
        printf "\n%s\n" "${delimiter}"
        printf "Accelerating launch.py..."
        printf "\n%s\n" "${delimiter}"
        prepare_tcmalloc
        accelerate launch --num_cpu_threads_per_process=6 "${LAUNCH_SCRIPT}" "$@"
    else
        printf "\n%s\n" "${delimiter}"
        printf "Launching launch.py..."
        printf "\n%s\n" "${delimiter}"
        prepare_tcmalloc
        "${python_cmd}" -u "${LAUNCH_SCRIPT}" "$@"
    fi

    if [[ ! -f tmp/restart ]]; then
        KEEP_GOING=0
    fi
done
