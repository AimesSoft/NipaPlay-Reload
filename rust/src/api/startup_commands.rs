use super::client_notifications::{notify_client, ClientNotification};

pub struct StartupCommand {
    pub launch_file_path: Option<String>,
    pub load_js_path: Option<String>,
}

pub fn parse_startup_command(args: Vec<String>) -> Result<StartupCommand, String> {
    let mut command = StartupCommand {
        launch_file_path: None,
        load_js_path: None,
    };
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        if arg == "--load-js" {
            let path = args
                .next()
                .filter(|value| !value.trim().is_empty() && !value.starts_with("--"))
                .ok_or_else(|| "--load-js 需要一个 JS 文件路径".to_string())?;
            if command.load_js_path.replace(path).is_some() {
                return Err("--load-js 只能使用一次".to_string());
            }
        } else if let Some(path) = arg.strip_prefix("--load-js=") {
            if path.trim().is_empty() {
                return Err("--load-js 需要一个 JS 文件路径".to_string());
            }
            if command.load_js_path.replace(path.to_string()).is_some() {
                return Err("--load-js 只能使用一次".to_string());
            }
        } else if arg.starts_with("-psn_") {
            continue;
        } else if arg.starts_with('-') {
            return Err(format!("未知启动参数: {arg}"));
        } else if command.launch_file_path.replace(arg).is_some() {
            return Err("只能传入一个启动文件路径".to_string());
        }
    }
    Ok(command)
}

pub fn report_startup_command_result(script_name: String, error: Option<String>) {
    let notification = match error {
        Some(error) => ClientNotification {
            title: "插件载入失败".to_string(),
            message: format!("{script_name}: {error}"),
        },
        None => ClientNotification {
            title: "插件已就绪".to_string(),
            message: format!("{script_name} 已自动载入并启用。"),
        },
    };
    notify_client(notification);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_command_with_existing_file_path() {
        let command = parse_startup_command(vec![
            "movie.mp4".into(),
            "--load-js".into(),
            "/tmp/source.js".into(),
        ])
        .unwrap();
        assert_eq!(command.launch_file_path.as_deref(), Some("movie.mp4"));
        assert_eq!(command.load_js_path.as_deref(), Some("/tmp/source.js"));
    }

    #[test]
    fn parses_equals_form() {
        let command = parse_startup_command(vec!["--load-js=source.js".into()]).unwrap();
        assert_eq!(command.load_js_path.as_deref(), Some("source.js"));
    }

    #[test]
    fn ignores_system_launch_marker() {
        let command = parse_startup_command(vec!["-psn_0_12345".into()]).unwrap();
        assert!(command.launch_file_path.is_none());
        assert!(command.load_js_path.is_none());
    }

    #[test]
    fn rejects_missing_or_repeated_options() {
        assert!(parse_startup_command(vec!["--load-js".into()]).is_err());
        assert!(parse_startup_command(vec!["--load-js".into(), "--other".into()]).is_err());
        assert!(
            parse_startup_command(vec!["--load-js=a.js".into(), "--load-js=b.js".into(),]).is_err()
        );
    }
}
