mod app;
mod git_ctx;
mod lima;
mod paths;
mod script;

use anyhow::Result;

fn main() -> Result<()> {
    app::run()
}
