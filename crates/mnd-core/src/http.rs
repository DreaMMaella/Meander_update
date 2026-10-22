//! Синхронный HTTP-клиент для блока `http_request`.
//!
//! Ядро в остальном декларируется как «без I/O, только порты», но файловые
//! реализации (`FsScriptAssetStore`, `FsSaveStore`) уже живут в `contracts.rs`,
//! поэтому сетевой запрос сделан так же: маленький синхронный помощник поверх
//! `ureq` (rustls). Блок исполняется внутри FFI-вызова на воркер-потоке,
//! поэтому блокировка на время запроса допустима.
//!
//! В веб-сборке (`--no-default-features`, фича `http-request` выключена)
//! клиент не собирается — `ring`/rustls это asm/C. Проверки URL и размеров
//! остаются общими, чтобы политика не зависела от платформы, а сам запрос
//! возвращает явную ошибку.

#[cfg(feature = "http-request")]
use std::io::Read;
#[cfg(feature = "http-request")]
use std::sync::OnceLock;
#[cfg(feature = "http-request")]
use std::time::Duration;

/// Таймаут HTTP-запроса блока `http_request`.
pub const HTTP_TIMEOUT_SECS: u64 = 15;
/// Максимальный размер тела запроса из квеста.
pub const MAX_HTTP_REQUEST_BODY_BYTES: usize = 1024 * 1024;
/// Максимальный размер ответа, передаваемого в переменную квеста.
pub const MAX_HTTP_RESPONSE_BYTES: usize = 4 * 1024 * 1024;

/// Общий HTTP-агент для всех запросов квеста.
/// Создаётся один раз и переиспользуется — это экономит на создании
/// TLS-контекста и пула соединений для каждого запроса.
#[cfg(feature = "http-request")]
fn shared_agent() -> &'static ureq::Agent {
    static AGENT: OnceLock<ureq::Agent> = OnceLock::new();
    AGENT.get_or_init(|| ureq::AgentBuilder::new().redirects(0).build())
}

/// Результат HTTP-запроса.
#[derive(Debug, Clone)]
pub struct HttpResponse {
    pub status: u16,
    pub body: String,
}

/// Выполнить синхронный HTTP-запрос.
///
/// * `method` — «GET»/«POST»/«PUT»/«DELETE»/«PATCH»/«HEAD» (без учёта регистра).
/// * `headers` — пары ключ→значение.
/// * `body` — тело запроса (для методов с телом; для GET/HEAD игнорируется).
///
/// Редиректы отключены намеренно: каждый новый destination должен пройти ту же
/// сетевую политику, а ureq не предоставляет здесь безопасного hook-а для
/// перепроверки каждого перехода. URL/response limits также защищают от
/// распространённых SSRF и memory-exhaustion обходов.
///
/// Политика (SSRF-проверка и лимиты тела) живёт здесь, а не в транспорт-ветке:
/// иначе правку «в веб-сборке это обошло бы» пришлось бы помнить дважды.
pub fn perform_http_request(
    method: &str,
    url: &str,
    headers: &[(String, String)],
    body: Option<&str>,
) -> Result<HttpResponse, String> {
    crate::network_safety::check_http_url(url)?;

    if let Some(body) = body
        && body.len() > MAX_HTTP_REQUEST_BODY_BYTES
    {
        return Err(format!(
            "тело HTTP-запроса слишком большое (максимум {} байт)",
            MAX_HTTP_REQUEST_BODY_BYTES
        ));
    }

    send(method, url, headers, body)
}

/// Транспорт с `ureq`.
#[cfg(feature = "http-request")]
fn send(
    method: &str,
    url: &str,
    headers: &[(String, String)],
    body: Option<&str>,
) -> Result<HttpResponse, String> {
    let agent = shared_agent();
    let mut request = agent
        .request(method, url)
        .timeout(Duration::from_secs(HTTP_TIMEOUT_SECS));
    for (key, value) in headers {
        request = request.set(key, value);
    }

    let with_body = body.is_some()
        && !method.eq_ignore_ascii_case("GET")
        && !method.eq_ignore_ascii_case("HEAD");

    let response = if with_body {
        request.send_string(body.unwrap_or_default())
    } else {
        request.call()
    }
    .map_err(|e| e.to_string())?;

    let status = response.status();
    let mut bytes = Vec::new();
    response
        .into_reader()
        .take((MAX_HTTP_RESPONSE_BYTES + 1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    if bytes.len() > MAX_HTTP_RESPONSE_BYTES {
        return Err(format!(
            "ответ HTTP слишком большой (максимум {} байт)",
            MAX_HTTP_RESPONSE_BYTES
        ));
    }
    let text = String::from_utf8(bytes)
        .map_err(|_| "ответ HTTP содержит некорректный UTF-8".to_string())?;
    Ok(HttpResponse { status, body: text })
}

/// Транспорт веб-сборки: сетью в браузере распоряжается не ядро, а JS-слой,
/// поэтому блок честно сообщает, что в этой сборке он не исполняется.
#[cfg(not(feature = "http-request"))]
fn send(
    method: &str,
    url: &str,
    _headers: &[(String, String)],
    _body: Option<&str>,
) -> Result<HttpResponse, String> {
    Err(format!(
        "HTTP-запрос {method} {url} в этой сборке недоступен — откройте квест в приложении"
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exposes_conservative_http_limits() {
        assert_eq!(HTTP_TIMEOUT_SECS, 15);
        assert_eq!(MAX_HTTP_REQUEST_BODY_BYTES, 1024 * 1024);
        assert_eq!(MAX_HTTP_RESPONSE_BYTES, 4 * 1024 * 1024);
    }
}
