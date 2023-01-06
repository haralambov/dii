#!/bin/bash

echo -n "Enter the username for which you'd like to make the setup: "
read USERNAME

if [ -z $USERNAME ]; then
    echo "Username is empty. Aborting..."
    exit;
fi

USER_EXISTS=$(grep -i $USERNAME /etc/shadow)
if [ -z $USER_EXISTS ]; then
    echo "User $USERNAME does not exist. Aborting..."
    exit;
fi

export PATH="$PATH:/usr/sbin"

function install_program() {
    echo -ne "Installing '$1'"
    OUTPUT=`apt install -y $1 2>&1`

    if [[ $? != 0 ]]; then
        echo "$OUTPUT"
        echo "Exiting..."
        exit;
    fi
    echo " - complete"
}

function add_user_to_sudoers() {
    USER_EXISTS_IN_SUDOERS=$(grep -i $USERNAME /etc/sudoers)
    if [[ -z "$USER_EXISTS_IN_SUDOERS" ]]; then
        echo "Adding '$USERNAME' to sudoers"
        echo "$USERNAME ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers
        return 0
    fi
    echo "User '$USERNAME' already exists in sudoers"
}

function add_contrib_and_non_free() {
    HAS_CONTRIB_AND_NON_FREE=$(grep -i "contrib non-free" /etc/apt/sources.list)
    if [[ -z "$HAS_CONTRIB_AND_NON_FREE" ]]; then
        echo -ne "Adding contrib and non-free to sources list and updating..."
        sed -i 's/deb.*/& contrib non-free/g' /etc/apt/sources.list
        apt update
    fi
}

function enable_firewall() {
    echo "Enabling the firewall"
    su - $USERNAME -c "sudo ufw enable"
    su - $USERNAME -c "sudo ufw status verbose"
}

function install_microcode() {
    IS_INTEL=$(cat /proc/cpuinfo | grep -i 'model name' | uniq | grep -i intel)
    if [[ -z "$IS_INTEL" ]]; then
        install_program amd64-microcode
    else
        install_program intel-microcode
    fi
}

function install_docker() {
    HAS_DOCKER=$(which docker)
    if [[ -z "$HAS_DOCKER" ]]; then
        echo "Installing docker"
        apt-get update;
        apt-get install -y ca-certificates curl gnupg lsb-release;
        mkdir -p /etc/apt/keyrings;
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg;
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt update;
        apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin;
        /usr/sbin/usermod -aG docker $USERNAME;
    fi
}

function install_nodejs() {
    mkdir -p /home/$USERNAME/node
    cd /home/$USERNAME/node

    wget https://nodejs.org/dist/v18.12.1/node-v18.12.1-linux-x64.tar.xz

    tar -xf node-v18.12.1-linux-x64.tar.xz
    cd node-v18.12.1-linux-x64
    mkdir /usr/local/bin/nodejs
    mv lib/ share/ include/ bin/ /usr/local/bin/nodejs

    FILES_TO_LINK=("node" "npm" "npx" "corepack")

    for FILE_TO_LINK in "${FILES_TO_LINK[@]}"; do
        if [ ! -f "/usr/local/bin/$FILE_TO_LINK" ]; then
            ln -s "/usr/local/bin/nodejs/bin/$FILE_TO_LINK" "/usr/local/bin/$FILE_TO_LINK"
        fi
    done

    rm -rf /home/$USERNAME/node
}

function cleanup() {
    echo "Cleanup..."
    apt purge -y vim-tiny vim-common notification-daemon xterm os-prober;
    apt clean && apt autoclean && apt autoremove
    # TODO: Remove dmenu if it doesn't break anything
}

function install_neovim() {
    NVIM_PATH=$(which nvim)
    if [[ -z "$NVIM_PATH" ]]; then
        wget https://github.com/neovim/neovim/releases/download/v0.8.2/nvim.appimage;
        mv nvim.appimage nvim;
        chmod +x nvim;
        mkdir -p /home/$USERNAME/.local/bin;
        mv nvim /usr/local/bin;
        chown -R $USERNAME:$USERNAME /home/$USERNAME/.local;
        su - $USERNAME -c "pip3 install pynvim neovim";
        su - $USERNAME -c "sh -c 'curl -fLo \"${XDG_DATA_HOME:-/home/$USERNAME/.local/share}\"/nvim/site/autoload/plug.vim --create-dirs \
           https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'";
    fi
}

function install_nerd_fonts() {
    FONTS_DIR="/home/$USERNAME/.local/share/fonts"
    if [ ! -d $FONTS_DIR ]; then
        mkdir -p $FONTS_DIR
    fi
    cd /home/$USERNAME/Downloads;
    wget https://github.com/ryanoasis/nerd-fonts/releases/download/v2.2.2/UbuntuMono.zip;
    unzip UbuntuMono.zip;
    mv *.ttf $FONTS_DIR
    rm UbuntuMono.zip
    chown -R $USERNAME:$USERNAME $FONTS_DIR
    su - $USERNAME -c "fc-cache -f -v"
}

function detect_sensors() {
    yes "" | sensors-detect
}

function add_xinitrc() {
    echo "Adding .xinitrc";
    echo "exec i3" >> /home/$USERNAME/.xinitrc;
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.xinitrc;
}

function add_user_dirs() {
    USER_DIRS=('Documents/notes' 'Downloads' 'Projects' 'Pictures/Screenshots' '.config')
    for i in "${USER_DIRS[@]}"; do
        if [ ! -d "/home/$USERNAME/$i" ]; then
            mkdir -p "/home/$USERNAME/$i";
            chown -R $USERNAME:$USERNAME /home/$USERNAME/$i;
        fi
    done
}

function change_folder_permissions() {
    chown -R $USERNAME:$USERNAME /home/$USERNAME
}

function add_config_files() {
    cd /home/$USERNAME/Projects;
    git clone https://github.com/haralambov/dotfiles.git;
    chown -R $USERNAME:$USERNAME /home/$USERNAME/Projects/dotfiles;
    cd /home/$USERNAME/Projects/dotfiles;
    su - $USERNAME -c "cd /home/$USERNAME/Projects/dotfiles && bash /home/$USERNAME/Projects/dotfiles/dotfile_mapper.sh"

    # enabling switch-on-connect module
    HAS_MODULE_ENABLED=$(grep '^load-module module-switch-on-connect' /etc/pulse/default.pa)
    if [ -z $HAS_MODULE_ENABLED ]; then
        echo "load-module module-switch-on-connect" >> /etc/pulse/default.pa
    fi
}

function install_programs() {
    PROGRAMS=(
        "sudo" "xorg" "git" "i3" "sakura" "feh" "htop" "rofi" "gxkb"
        "thunar" "thunar-archive-plugin" "firefox-esr" "screenfetch" "ripgrep" "curl" "tlp"
        "lm-sensors" "ufw" "redshift" "unzip" "zip" "unrar" "arandr"
        "mlocate" "tree" "python3-pip" "fuse" "snapd" "keepassxc"
        "mpv" "psmisc" "pavucontrol" "pipewire" "pipewire-audio-client-libraries"
        "ncal" "libnotify-bin" "playerctl" "pulseaudio" "pulseaudio-utils"
        "libspa-0.2-bluetooth" # pipewire dependency for bluetooth audio
        "blueman" "i3blocks" "lxappearance" 
        "network-manager" "network-manager-gnome" # for applet
        "xautolock" "diodon" "compton"
        "xdotool" "solaar" "tmux" "zsh" "zathura"
    )

    for PROGRAM in "${PROGRAMS[@]}"; do
        install_program $PROGRAM
    done
}

function install_rust() {
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
}

function install_oh_my_zsh() {
    su - $USERNAME -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
}

add_contrib_and_non_free
install_programs
add_user_to_sudoers
detect_sensors
enable_firewall

install_microcode
install_program firmware-iwlwifi

install_docker
install_nodejs
install_program docker-compose
install_program qbittorrent

install_neovim

add_xinitrc
add_user_dirs
install_nerd_fonts

add_config_files
change_folder_permissions

install_rust
install_oh_my_zsh

cleanup
