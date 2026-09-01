use std::{env, fs};

use zed::settings::LspSettings;
use zed::{LanguageServerId, Worktree};
use zed_extension_api as zed;

const PACKAGE_NAME: &str = "@arkts/language-server";
const PACKAGE_VERSION: &str = "1.3.10";
const SERVER_MODULE: &str = "node_modules/@arkts/language-server/out/index.mjs";
const PROXY_FILE: &str = "ets-language-server.mjs";
const PROXY_SOURCE: &str = include_str!("../assets/ets-language-server.mjs");
const DIAGNOSTIC_SERVER_SOURCE: &[u8] = include_bytes!("../assets/diagnostic-language-server.mjs");

struct ArkTsDevEcoExtension {
    cached_proxy_path: Option<String>,
}

fn with_semantic_tokens_default(
    mut options: zed::serde_json::Value,
) -> Result<zed::serde_json::Value, String> {
    let root = options
        .as_object_mut()
        .ok_or_else(|| "ArkTS initialization_options must be a JSON object".to_string())?;
    let ets = root
        .entry("ets")
        .or_insert_with(|| zed::serde_json::json!({}))
        .as_object_mut()
        .ok_or_else(|| "ArkTS initialization_options.ets must be a JSON object".to_string())?;
    ets.entry("semanticTokens")
        .or_insert(zed::serde_json::Value::Bool(false));
    Ok(options)
}

impl ArkTsDevEcoExtension {
    fn server_exists() -> bool {
        fs::metadata(SERVER_MODULE).is_ok_and(|metadata| metadata.is_file())
    }

    fn ensure_language_server(&self, language_server_id: &LanguageServerId) -> Result<(), String> {
        zed::set_language_server_installation_status(
            language_server_id,
            &zed::LanguageServerInstallationStatus::CheckingForUpdate,
        );

        let installed = zed::npm_package_installed_version(PACKAGE_NAME)?;
        if installed.as_deref() != Some(PACKAGE_VERSION) || !Self::server_exists() {
            zed::set_language_server_installation_status(
                language_server_id,
                &zed::LanguageServerInstallationStatus::Downloading,
            );
            zed::npm_install_package(PACKAGE_NAME, PACKAGE_VERSION)?;
        }

        if !Self::server_exists() {
            return Err(format!(
                "installed {PACKAGE_NAME}@{PACKAGE_VERSION}, but {SERVER_MODULE} is missing"
            ));
        }

        let installed_server = fs::read(SERVER_MODULE).ok();
        if installed_server.as_deref() != Some(DIAGNOSTIC_SERVER_SOURCE) {
            fs::write(SERVER_MODULE, DIAGNOSTIC_SERVER_SOURCE).map_err(|error| {
                format!("failed to install diagnostic ArkTS language server: {error}")
            })?;
        }

        zed::set_language_server_installation_status(
            language_server_id,
            &zed::LanguageServerInstallationStatus::None,
        );
        Ok(())
    }

    fn proxy_path(&mut self) -> Result<String, String> {
        if let Some(path) = &self.cached_proxy_path {
            if fs::read_to_string(path).ok().as_deref() == Some(PROXY_SOURCE) {
                return Ok(path.clone());
            }
        }

        fs::write(PROXY_FILE, PROXY_SOURCE)
            .map_err(|error| format!("failed to write ArkTS LSP proxy: {error}"))?;
        let path = env::current_dir()
            .map_err(|error| format!("failed to locate extension work directory: {error}"))?
            .join(PROXY_FILE)
            .to_string_lossy()
            .into_owned();
        self.cached_proxy_path = Some(path.clone());
        Ok(path)
    }
}

impl zed::Extension for ArkTsDevEcoExtension {
    fn new() -> Self {
        Self {
            cached_proxy_path: None,
        }
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &Worktree,
    ) -> Result<zed::Command, String> {
        if let Ok(settings) = LspSettings::for_worktree(language_server_id.as_ref(), worktree) {
            if let Some(binary) = settings.binary {
                if let Some(command) = binary.path {
                    return Ok(zed::Command {
                        command,
                        args: binary.arguments.unwrap_or_default(),
                        env: binary.env.unwrap_or_default().into_iter().collect(),
                    });
                }
            }
        }

        self.ensure_language_server(language_server_id)?;
        let proxy = self.proxy_path()?;
        let node = match worktree.which("node") {
            Some(node) => node,
            None => zed::node_binary_path()?,
        };

        Ok(zed::Command {
            command: node,
            args: vec![proxy, "--stdio".to_string()],
            env: Vec::new(),
        })
    }

    fn language_server_initialization_options(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &Worktree,
    ) -> Result<Option<zed::serde_json::Value>, String> {
        let options = LspSettings::for_worktree(language_server_id.as_ref(), worktree)
            .ok()
            .and_then(|settings| settings.initialization_options)
            .unwrap_or_else(|| zed::serde_json::json!({ "debug": false }));
        Ok(Some(with_semantic_tokens_default(options)?))
    }
}

zed::register_extension!(ArkTsDevEcoExtension);

#[cfg(test)]
mod tests {
    use super::{with_semantic_tokens_default, zed};

    #[test]
    fn disables_semantic_tokens_by_default() {
        let options = with_semantic_tokens_default(zed::serde_json::json!({ "debug": false }))
            .expect("valid initialization options");

        assert_eq!(options["ets"]["semanticTokens"], false);
    }

    #[test]
    fn preserves_explicit_semantic_tokens_setting() {
        let options = with_semantic_tokens_default(zed::serde_json::json!({
            "ets": { "semanticTokens": true }
        }))
        .expect("valid initialization options");

        assert_eq!(options["ets"]["semanticTokens"], true);
    }
}
