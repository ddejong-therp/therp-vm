{
  description = "A flake to manage odoo with git-aggregator and pip";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, flake-utils, nixpkgs }: flake-utils.lib.eachSystem flake-utils.lib.allSystems (system:
      let
        imageUrl = "https://releases.ubuntu.com/jammy/ubuntu-22.04.5-live-server-amd64.iso";
        pkgs = nixpkgs.legacyPackages.${system};
        buildVm = pkgs.writers.writeBashBin "build" ''
          set -ex
          
          if [ ! -f install.iso ]; then
            ${pkgs.wget}/bin/wget -O install.iso ${imageUrl}
          fi
          
          ${pkgs.qemu_kvm}/bin/qemu-img create -f qcow2 ~/vm.img 64G
          ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 -enable-kvm -boot d \
            -cdrom install.iso -m 4G -cpu host -smp 2 -hda ~/vm.img
        '';

        runVm = pkgs.writers.writeBashBin "run" ''
          set -e

          ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 -enable-kvm -boot d \
            -m 4G -cpu host -smp 2 -hda ~/vm.img \
            -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8069-:8069,hostfwd=tcp::8072-:8072 \
            -device virtio-net-pci,netdev=net0
        '';

        runShell = pkgs.writers.writeBashBin "run-shell" ''
          set -e
          "${runVm}/bin/run" &
          sleep 10
          "${shellVm}/bin/shell"
        '';

        setupVm = pkgs.writers.writeBashBin "setup" ''
          set -e

          scp -P 2222 ~/.ssh/id_rsa.pub root@localhost:~/.ssh/authorized_keys
          scp -P 2222 ~/.ssh/id_rsa.pub therp@localhost:~/.ssh/authorized_keys
          ssh -A -p 2222 root@localhost <<HEREDOC
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get upgrade -y
            apt-get install -y --no-install-recommends \
              build-essential bzip2 ca-certificates curl git gettext libssl-dev locales-all \
              libxslt1.1 liblcms2-2 libldap2-dev libpq5 libsasl2-2 \
              libtinfo-dev libncurses5-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
              libncursesw5-dev tk-dev libxmlsec1-dev libffi-dev liblzma-dev adduser lsb-base libxml2-dev \
              libxslt1-dev libpq-dev libsasl2-dev libopenjp2-7-dev \
              libtiff5-dev libfreetype6-dev liblcms2-dev libwebp-dev openssh-server nano \
              postgresql pre-commit python3-dev ripgrep rsync wget
            pip install "python-lsp-server[all]"
            pip install pylint-odoo
            if [ ! -d /nix ]; then
              curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes
            fi

            sudo -u postgres psql -c "CREATE ROLE therp WITH LOGIN SUPERUSER"
            sudo -u therp createdb therp
            service postgresql restart

            echo "alias vi=nvim" >> /home/therp/.profile
            echo "alias g=git" >> /home/therp/.profile
            mkdir -p /home/therp/.config/nvim
            echo "luafile /etc/xdg/nvim/init.lua" > /home/therp/.config/nvim/init.vim
            echo "local all all trust" > /var/lib/postgresql/14/main/pg_hba.conf
            echo "host all all 127.0.0.1/32 trust" >> /var/lib/postgresql/14/main/pg_hba.conf
            echo "host all all ::1/128 trust" >> /var/lib/postgresql/14/main/pg_hba.conf

            mkdir -p /root/.ssh
            mkdir -p /home/therp/.ssh
            chown therp:therp /home/therp/.ssh
          HEREDOC
          ssh -p 2222 root@localhost <<HEREDOC
            nix-env -iA nixpkgs.neovim nixpkgs.rustup
          HEREDOC
          ssh -p 2222 therp@localhost <<HEREDOC
            git config --global user.name "Danny de Jong"
            git config --global user.email "ddejong@therp.nl"
          HEREDOC
        '';

        shellVm = pkgs.writers.writeBashBin "shell" ''
          set -e

          rsync -IL -e "ssh -p 2222" /etc/gitconfig root@localhost:/etc/gitconfig
          rsync -IL -e "ssh -p 2222" ~/.config/pylintrc therp@localhost:~/.config/pylintrc
          rsync -IL -e "ssh -p 2222" ~/.pydocstyle.ini therp@localhost:~/.pydocstyle.ini
          rsync -IL -e "ssh -p 2222" ~/code/odools.toml therp@localhost:~/odools.toml
          rsync -ILr --del -e "ssh -p 2222" /etc/xdg/nvim root@localhost:/etc/xdg
          rsync -ILr --del -e "ssh -p 2222" ~/.config/nvim therp@localhost:~/.config
          ssh -A -p 2222 therp@localhost
        '';
      in {
        apps = {
          install = {
            "type" = "app";
            "program" = "${buildVm}/bin/build";
          };
          run = {
            "type" = "app";
            "program" = "${runVm}/bin/run";
          };
          setup = {
            "type" = "app";
            "program" = "${setupVm}/bin/setup";
          };
          shell = {
            "type" = "app";
            "program" = "${shellVm}/bin/shell";
          };
          default = {
            "type" = "app";
            "program" = "${runShell}/bin/run-shell";
          };
        };
      });
}
