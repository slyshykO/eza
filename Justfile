all: build test
all-release: build-release test-release


#----------#
# building #
#----------#

# compile the exa binary
@build:
    cargo build

# compile the exa binary (in release mode)
@build-release:
    cargo build --release --verbose

# produce an HTML chart of compilation timings
@build-time:
    cargo +nightly clean
    cargo +nightly build -Z timings

# check that the exa binary can compile
@check:
    cargo check


#---------------#
# running tests #
#---------------#

# run unit tests
@test:
    cargo test --workspace -- --quiet

# run unit tests (in release mode)
@test-release:
    cargo test --workspace --release --verbose

#-----------------------#
# code quality and misc #
#-----------------------#

# lint the code
@clippy:
    touch src/main.rs
    cargo clippy

# update dependency versions, and checks for outdated ones
@update-deps:
    cargo update
    command -v cargo-outdated >/dev/null || (echo "cargo-outdated not installed" && exit 1)
    cargo outdated

# list unused dependencies
@unused-deps:
    command -v cargo-udeps >/dev/null || (echo "cargo-udeps not installed" && exit 1)
    cargo +nightly udeps

# check that every combination of feature flags is successful
@check-features:
    command -v cargo-hack >/dev/null || (echo "cargo-hack not installed" && exit 1)
    cargo hack check --feature-powerset

# print versions of the necessary build tools
@versions:
    rustc --version
    cargo --version


#---------------#
# documentation #
#---------------#

# build the man pages
@man:
    mkdir -p "${CARGO_TARGET_DIR:-target}/man"
    pandoc --standalone -f markdown -t man man/eza.1.md        > "${CARGO_TARGET_DIR:-target}/man/eza.1"
    pandoc --standalone -f markdown -t man man/eza_colors.5.md > "${CARGO_TARGET_DIR:-target}/man/eza_colors.5"
    pandoc --standalone -f markdown -t man man/eza_colors-explanation.5.md > "${CARGO_TARGET_DIR:-target}/man/eza_colors-explanation.5"

# build and preview the main man page (eza.1)
@man-1-preview: man
    man "${CARGO_TARGET_DIR:-target}/man/eza.1"

# build and preview the colour configuration man page (eza_colors.5)
@man-5-preview: man
    man "${CARGO_TARGET_DIR:-target}/man/eza_colors.5"

# build and preview the colour configuration man page (eza_colors.5)
@man-5-explanations-preview: man
    man "${CARGO_TARGET_DIR:-target}/man/eza_colors-explanation.5"

#---------------#
#    release    #
#---------------#

# If you're not cafkafk and she isn't dead, don't run this!
# 
# usage: release major, release minor, release patch
@release version: 
    cargo bump '{{version}}'
    git cliff -t $(grep '^version' Cargo.toml | head -n 1 | grep -E '([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+)?' -o) > CHANGELOG.md
    cargo check
    nix build -L ./#clippy
    git checkout -b cafk-release-$(grep '^version' Cargo.toml | head -n 1 | grep -E '([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+)?' -o)
    git commit -asm "chore: release $(grep '^version' Cargo.toml | head -n 1 | grep -E '([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+)?' -o)"
    git push
    echo "waiting 10 seconds for github to catch up..."
    sleep 10
    gh pr create --draft --title "chore: release $(grep '^version' Cargo.toml | head -n 1 | grep -E '([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+)?' -o)" --body "This PR was auto-generated by our lovely just file" --reviewer cafkafk 

#----------------#
#    binaries    #
#----------------#

tar BINARY TARGET:
    tar czvf ./target/"bin-$(convco version)"/{{BINARY}}_{{TARGET}}.tar.gz -C ./target/{{TARGET}}/release/ ./{{BINARY}}

zip BINARY TARGET:
    zip -j ./target/"bin-$(convco version)"/{{BINARY}}_{{TARGET}}.zip ./target/{{TARGET}}/release/{{BINARY}}

binary BINARY TARGET:
    rustup target add {{TARGET}}
    cross build --release --target {{TARGET}}
    just tar {{BINARY}} {{TARGET}}
    just zip {{BINARY}} {{TARGET}}

checksum:
    echo "# Checksums"
    echo "## sha256sum"
    echo '```'
    sha256sum ./target/"bin-$(convco version)"/*
    echo '```'
    echo "## md5sum"
    echo '```'
    md5sum ./target/"bin-$(convco version)"/*
    echo '```'

alias c := cross

# Generate release binaries for EZA
# 
# usage: cross
@cross: 
    # Setup Output Directory
    mkdir -p ./target/"bin-$(convco version)"

    # Install Toolchains/Targets
    rustup toolchain install stable

    ## Linux
    ### x86
    just binary eza x86_64-unknown-linux-gnu
    just binary eza x86_64-unknown-linux-musl

    ### aarch
    just binary eza aarch64-unknown-linux-gnu

    ### arm
    just binary eza arm-unknown-linux-gnueabihf

    ## MacOS
    # TODO: just binary eza x86_64-apple-darwin

    ## Windows
    ### x86
    just binary eza.exe x86_64-pc-windows-gnu
    # TODO: just binary eza.exe x86_64-pc-windows-gnullvm
    # TODO: just binary eza.exe x86_64-pc-windows-msvc

    # Generate Checksums
    just checksum

#---------------------#
# Integration testing #
#---------------------#

alias gen := gen_test_dir

test_dir := "tests/test_dir"

gen_test_dir:
    #!/usr/bin/env bash
    rm {{test_dir}} -r;
    mkdir -p {{test_dir}}
    cd {{test_dir}};

    # BEGIN grid
    mkdir -p grid
    cd grid

    mkdir $(seq -w 001 1000);
    seq 0001 1000 | split -l 1 -a 3 -d - file_

    # Set time to unix epoch
    touch --date=@0 *;

    cd ..

    # END grid

    # BEGIN git
    
    mkdir -p git
    cd git

    mkdir $(seq -w 001 10);
    for f in ./*
    do
        cd $f
        git init
        seq 01 10 | split -l 1 -a 3 -d - file_
        cd ..
    done

    cd ..
    
    # END git
    eza -l --grid;

# Runs integration tests in nix sandbox
#
# Required nix, likely won't work on windows.
@itest:
    nix build -L ./#trycmd

# Runs integration tests in nix sandbox, and dumps outputs.
#
# WARNING: this can cause loss of work
@idump:
    rm ./tests/cmd/*nix.stderr -f || echo  
    rm ./tests/cmd/*nix.stdout -f || echo
    nix build -L ./#trydump
    cp ./result/dump/*nix.* ./tests/cmd/

