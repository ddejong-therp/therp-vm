{
  description = "A flake to manage odoo with git-aggregator and pip";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, flake-utils, nixpkgs }: flake-utils.lib.eachSystem flake-utils.lib.allSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        buildVm = pkgs.writers.writeBashBin "build" ''
          set -ex
          
          if [ ! -f install.iso ]; then
            ${pkgs.wget}/bin/wget -O install.iso https://cdimage.debian.org/debian-cd/13.0.0/amd64/iso-cd/debian-13.0.0-amd64-netinst.iso
          fi
          
          ${pkgs.qemu_kvm}/bin/qemu-img create -f qcow2 ~/vm.img 64G
          ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 -enable-kvm -boot d \
            -cdrom install.iso -m 4G -cpu host -smp 2 -hda ~/vm.img
        '';

        runVm = pkgs.writers.writeBashBin "run" ''
          set -e

          ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 -enable-kvm -boot d \
            -m 4G -cpu host -smp 2 -hda ~/vm.img \
            -netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=net0
        '';

        runShell = pkgs.writers.writeBashBin "run-shell" ''
          set -e
          "${runVm}/bin/run" &
          sleep 10
          "${shellVm}/bin/shell"
        '';

        setupVm = pkgs.writers.writeBashBin "setup" ''
          set -e

          export DEBIAN_FRONTEND=noninteractive
          apt-get update
          apt-get upgrade -y
          apt-get install -y --no-install-recommends \
            build-essential bzip2 ca-certificates curl git gettext libssl-dev locales-all \
            libxslt1.1 liblcms2-2 libldap2-dev libpq5 libsasl2-2 \
            libtinfo-dev libncurses5-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
            libncursesw5-dev tk-dev libxmlsec1-dev libffi-dev liblzma-dev adduser lsb-base libxml2-dev \
            libxslt1-dev libpq-dev libsasl2-dev libopenjp2-7-dev \
            libtiff5-dev libfreetype6-dev liblcms2-dev libwebp-dev openssh-server nano pipx pre-commit \
            python3-dev rsync wget
          pipx install "python-lsp-server[all]"
          if [ ! -d /nix ]; then
            curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes
          fi

          git config --global user.name "Danny de Jong"
          git config --global user.email "ddejong@therp.nl"

          echo "alias vi=nvim" >> /home/therp/.profile
          mkdir -p /home/therp/.config/nvim
          echo "luafile /etc/xdg/nvim/init.lua" > /home/therp/.config/nvim/init.vim
        '';

        shellVm = pkgs.writers.writeBashBin "shell" ''
          set -e

          scp -P 2222 /etc/gitconfig root@localhost:/etc/gitconfig
          scp -r -P 2222 /etc/xdg/nvim root@localhost:/etc/xdg/nvim
          #rsync e "ssh -p 2222" /etc/xdg/nvim root@localhost:2222:/etc/xdg
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
