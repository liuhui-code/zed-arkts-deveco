use std::{env, fs};

use zed::settings::LspSettings;
use zed::{LanguageServerId, Worktree};
use zed_extension_api as zed;

const PACKAGE_NAME: &str = "@arkts/language-server";
const PACKAGE_VERSION: &str = "1.3.10";
const SERVER_MODULE: &str = "node_modules/@arkts/language-server/out/index.mjs";
const PROXY_FILE: &str = "ets-language-server.mjs";
const PROXY_SOURCE: &str = include_str!("../assets/ets-language-server.mjs");

struct ArkTsDevEcoExtension {
    cached_proxy_path: Option<String>,
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
        _worktree: &Worktree,
    ) -> Result<zed::Command, String> {
        self.ensure_language_server(language_server_id)?;
        let proxy = self.proxy_path()?;

        Ok(zed::Command {
            command: zed::node_binary_path()?,
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
        Ok(Some(options))
    }
}

zed::register_extension!(ArkTsDevEcoExtension);
