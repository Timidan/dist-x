use clap::Parser;
use distributionx_cli::{args, commands};

fn main() {
    let cli = args::Cli::parse();
    commands::run(cli);
}
