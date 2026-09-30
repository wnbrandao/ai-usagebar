//! Launch the bundled WPF corner widget without requiring Python or a loose script.

use std::fs::OpenOptions;
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};

use serde_json::{Value, json};

const SCRIPT: &str = include_str!("../../windows/corner-widget.ps1");

fn widget_dir() -> Result<PathBuf, String> {
    let local = std::env::var_os("LOCALAPPDATA").ok_or("LOCALAPPDATA is unset")?;
    let dir = PathBuf::from(local).join("ai-usagebar").join("widget");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

pub(super) fn save_display(value: &Value) -> Result<(), String> {
    let visible: Vec<&str> = value
        .get("visible")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .filter(|id| !id.is_empty() && id.len() <= 128 && !id.chars().any(char::is_control))
        .take(100)
        .collect();
    let theme = match value.get("theme").and_then(Value::as_str) {
        Some("dark") => "dark",
        _ => "light",
    };
    let show_as = match value.get("showAs").and_then(Value::as_str) {
        Some("left") => "left",
        _ => "used",
    };
    let data = json!({"visible": visible, "theme": theme, "showAs": show_as});
    std::fs::write(widget_dir()?.join("display.json"), data.to_string()).map_err(|e| e.to_string())
}

pub(super) fn open() -> Result<(), String> {
    let dir = widget_dir()?;
    let script = dir.join("corner-widget.ps1");
    // Replacing our own bundled script on every launch also upgrades a widget
    // left over from an older tray release.
    std::fs::write(&script, SCRIPT).map_err(|e| e.to_string())?;
    let usage = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join("ai-usagebar.exe")))
        .filter(|path| path.is_file())
        .unwrap_or_else(|| PathBuf::from("ai-usagebar.exe"));
    let log = OpenOptions::new()
        .create(true)
        .append(true)
        .open(dir.join("corner-widget.log"))
        .map_err(|e| e.to_string())?;
    Command::new("powershell.exe")
        .args([
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-WindowStyle",
            "Hidden",
            "-STA",
            "-File",
        ])
        .arg(script)
        .arg(usage)
        .creation_flags(0x0800_0000) // CREATE_NO_WINDOW
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::from(log))
        .spawn()
        .map(|_| ())
        .map_err(|e| e.to_string())
}
