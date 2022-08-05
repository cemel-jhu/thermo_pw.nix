{
  description = "expose as a flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        system = "x86_64-linux";
        pkgs = import nixpkgs {
          inherit system;
        };
        thermo-pw.dev = pkgs.fetchFromGitHub
          {
            owner = "dalcorso";
            repo = "thermo_pw";
            rev = "1.7.1";
            sha256 = "5ovjWkVviGd7STtmlO52iJxEwtFtO7iclq1p5tDWvts=";
          };
        fox-xml.dev = pkgs.fetchFromGitHub
          {
            owner = "pietrodelugas";
            repo = "fox";
            rev = "3453648e6837658b747b895bb7bef4b1ed2eac40";
            sha256 = "WExpkXkiqbp7J09RPJCb9jyizOD5X/VP6BTwRXCgaIs=";
          };
        devx.dev = pkgs.fetchFromGitLab {
          owner = "max-centre";
          repo = "components/devicexlib";
          rev = "0.2.0";
          sha256 = "EYDRmGgLdmqm7AjNJj2ENv8Q/8jO2YBwsyuZYHjF3qU=";
        };
        libmbd.dev = pkgs.fetchFromGitHub
          {
            owner = "libmbd";
            repo = "libmbd";
            rev = "82005cbb65bdf5d32ca021848eec8f19da956a77";
            # rev = "0.12.5";
            sha256 = "lFyGeHThXwCUbv7cwG5PK6s4T19Ex33WJEcHYX89QTE=";
          };

        useMpi = true;
        requirements = with pkgs; [ fftw blas lapack git gnum4 ] ++ (lib.optionals useMpi [ mpi ]);
        quantum-espresso-mpi-thermo-pw = with pkgs; stdenv.mkDerivation rec {
          version = "7.1";
          pname = "quantum-espresso";

          src = fetchFromGitLab {
            owner = "QEF";
            repo = "q-e";
            rev = "qe-${version}";
            sha256 = "lacdpi9bz90JLwfeZT3O5y3O+SK6k6SBoD4CoPwYWtE=";
          };

          passthru = {
            inherit mpi;
          };

          patchPhase = ''
            # Submodule deps
            mkdir -p external/
            cp -pR ${fox-xml.dev}/* external/fox
            cp -pR ${devx.dev}/* external/devxlib
            cp -pR ${libmbd.dev}/* external/mbd

            # Fool makefile that we cloned dep
            mkdir external/fox/.git
            mkdir external/devxlib/.git
            mkdir external/mbd/.git

            # Extension dep
            cp -pR ${thermo-pw.dev} thermo_pw

            # Write permissions are borked
            chmod -R +w thermo_pw
            chmod -R +w external

            # Patch for extension
            cd thermo_pw
            make join_qe
            cd ..
          '';

          preConfigure = ''
            patchShebangs configure
          '';

          nativeBuildInputs = [ gfortran ];
          buildInputs = requirements;
          configureFlags =
            if
              useMpi then
              [ "LD=${mpi}/bin/mpif90" ]
            else [ "LD=${gfortran}/bin/gfortran" ];
          makeFlags = [ "thermo_pw" ];
        };
      in
      {
        devShells.default = with pkgs;
          pkgs.mkShell rec {
            packages = requirements ++ [ quantum-espresso-mpi-thermo-pw gnuplot ];

            shellHook = ''
              # Create the temp directories required for usage.
              mkdir -p $PSEUDO_DIR $TMP_DIR

              # Set a hostfile for local mpi
              echo "localhost slots=25" > $TMP_QE/hostfile

              # Export Q-E check failure function
              check_failure () {
                  # usage: check_failure $?
                  if test $1 != 0
                  then
                      echo "Error condition encountered during test: exit status = $1"
                      echo "Aborting"
                      exit 1
                  fi
              }
              export -f check_failure
            '';

            # Q-E Variables
            PREFIX = "${quantum-espresso-mpi-thermo-pw.src}";
            BIN_DIR = "${quantum-espresso-mpi-thermo-pw}/bin";
            TMP_QE = "/tmp/q-e";
            PSEUDO_DIR = "${TMP_QE}/pseudo";
            TMP_DIR = "${TMP_QE}/tempdir";

            PARA_PREFIX = " ";
            PARA_POSTFIX = " -nk 1 -nd 1 -nb 1 -nt 1 ";

            OMP_NUM_THREADS = "1";
            NUM_PROCESSORS = "4";
            PARA_IMAGE_POSTFIX = "-ni 2 ${PARA_POSTFIX}";
            PARA_IMAGE_PREFIX = "mpirun -np ${NUM_PROCESSORS} " +
              "--hostfile ${TMP_QE}/hostfile";

            WGET = "curl -o";
            LC_ALL = "C";
            NETWORK_PSEUDO = "https://pseudopotentials.quantum-espresso.org/upf_files/";
          };
        packages.default = quantum-espresso-mpi-thermo-pw;
      });
}
