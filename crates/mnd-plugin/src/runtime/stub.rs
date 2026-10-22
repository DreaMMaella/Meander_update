//! Заглушка [`PluginInstance`] для сборок без `mlua` (веб).
//!
//! Плагин = Lua-код, а Lua в wasm не собирается, поэтому плагин здесь не
//! поднимается никогда. Тип и методы сохранены один в один: хост, `mnd-ffi` и
//! Dart-биндинги не должны знать, какой из двух вариантов скомпилирован.
//!
//! Проверка манифеста и разрешений оставлена не для пользы веб-плеера, а ради
//! паритета сообщений: на одинаковый `plugin.json` редактор и веб выдают одну и
//! ту же ошибку конфигурации, прежде чем сказать «плагинов нет».

use serde_json::{Map, Value};

use super::{CallContext, InvocationOutcome, PluginError};
use crate::manifest::PluginManifest;
use crate::policy::Policy;

pub struct PluginInstance {
    manifest: PluginManifest,
    policy: Policy,
    storage: Map<String, Value>,
}

impl PluginInstance {
    pub fn new(
        manifest: PluginManifest,
        _source: &str,
        _storage: Option<Value>,
    ) -> Result<Self, PluginError> {
        let mut errors = manifest.validate().err().unwrap_or_default();
        // Права всё равно проверяются: манифест с неизвестным разрешением
        // должен быть отвергнут и здесь, иначе заглушка молча пропускала бы
        // битый плагин там, где нативная сборка его ругает.
        let (_policy, permission_errors) = Policy::from_names(&manifest.permissions);
        errors.extend(permission_errors);
        if !errors.is_empty() {
            return Err(PluginError(errors));
        }

        Err(PluginError(vec![format!(
            "плагин '{}' требует Lua, а в этой сборке его нет — откройте квест в приложении",
            manifest.id
        )]))
    }

    pub fn manifest(&self) -> &PluginManifest {
        &self.manifest
    }

    pub fn id(&self) -> &str {
        &self.manifest.id
    }

    pub fn policy(&self) -> &Policy {
        &self.policy
    }

    pub fn storage(&self) -> Value {
        Value::Object(self.storage.clone())
    }

    pub fn subscribes_to(&self, _event: &str) -> bool {
        false
    }

    pub fn invoke_event(
        &mut self,
        _event: &str,
        _payload: Value,
        _context: &CallContext,
    ) -> InvocationOutcome {
        InvocationOutcome::failed(&self.manifest.id, "плагины недоступны в этой сборке")
    }

    pub fn call_function(
        &mut self,
        name: &str,
        _args: Value,
        _context: &CallContext,
    ) -> InvocationOutcome {
        InvocationOutcome::failed(
            &self.manifest.id,
            format!("плагины недоступны в этой сборке (функция '{name}')"),
        )
    }
}
