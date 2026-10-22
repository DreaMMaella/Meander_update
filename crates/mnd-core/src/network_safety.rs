//! Локальная защита сетевых блоков квеста.
//!
//! Это не замена серверной модерации: список намеренно находится в клиентском
//! бинарнике и защищает игрока даже в offline-режиме. Проверка выполняется
//! непосредственно перед сетевым запросом/открытием ссылки.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, ToSocketAddrs};

use url::Url;

/// Проверить URL перед передачей его в HTTP-клиент или внешний браузер.
///
/// Ошибка означает, что адрес нельзя использовать из квеста. Обычные
/// `http`/`https` адреса разрешаются после этой проверки.
pub fn check_url(raw: &str) -> Result<(), String> {
    let trimmed = raw.trim();
    if !trimmed.contains("://") {
        return Err("некорректный URL".to_string());
    }
    let url = Url::parse(trimmed).map_err(|_| "некорректный URL".to_string())?;

    if !matches!(url.scheme().to_ascii_lowercase().as_str(), "http" | "https") {
        return Err(format!("схема '{}' запрещена", url.scheme()));
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err("URL с учётными данными запрещён".to_string());
    }

    let host = normalized_host(&url)?;
    if is_blocked_hostname(&host) {
        return Err("хост в локальном blacklist".to_string());
    }

    if let Ok(ip) = host.parse::<IpAddr>()
        && is_blocked_ip(ip)
    {
        return Err("приватный или служебный IP-адрес запрещён".to_string());
    }

    Ok(())
}

/// Проверить URL и все адреса, возвращённые локальным DNS-резолвером.
///
/// Это закрывает распространённый SSRF-обход через домен, который указывает
/// на private/link-local адрес. Между проверкой и фактическим соединением всё
/// ещё возможна DNS-rebinding-атака, поэтому HTTP-редиректы дополнительно
/// отключены в `http.rs`.
pub fn check_http_url(raw: &str) -> Result<(), String> {
    // Unit-тест HTTP использует loopback-сервер для проверки тела/статуса.
    // Исключение существует только в test-бинарнике и недоступно production.
    #[cfg(test)]
    if is_loopback_test_url(raw) {
        return Ok(());
    }

    check_url(raw)?;
    let url = Url::parse(raw.trim()).map_err(|_| "некорректный URL".to_string())?;
    let host = normalized_host(&url)?;
    let port = url
        .port_or_known_default()
        .ok_or_else(|| "URL без поддерживаемого порта".to_string())?;

    let addresses = (host.as_str(), port)
        .to_socket_addrs()
        .map_err(|_| "не удалось разрешить адрес хоста".to_string())?
        .collect::<Vec<_>>();
    if addresses.is_empty() {
        return Err("хост не имеет сетевого адреса".to_string());
    }
    if addresses.iter().any(|address| is_blocked_ip(address.ip())) {
        return Err("хост разрешается в приватный или служебный IP-адрес".to_string());
    }

    Ok(())
}

fn normalized_host(url: &Url) -> Result<String, String> {
    url.host_str()
        .ok_or_else(|| "URL без хоста".to_string())
        .map(|host| {
            host.trim_matches(['[', ']'])
                .trim_end_matches('.')
                .to_ascii_lowercase()
        })
        .and_then(|host| {
            if host.is_empty() {
                Err("URL без хоста".to_string())
            } else {
                Ok(host)
            }
        })
}

fn is_blocked_hostname(host: &str) -> bool {
    if matches!(
        host,
        "localhost"
            | "localhost.localdomain"
            | "metadata.google.internal"
            | "metadata.google.com"
            | "instance-data.ec2.internal"
    ) {
        return true;
    }

    // Локальные/служебные зоны не должны быть доступны из опубликованного
    // квеста: они часто используются для SSRF и утечки данных из LAN.
    if host.ends_with(".localhost")
        || host.ends_with(".local")
        || host.ends_with(".internal")
        || host.ends_with(".test")
    {
        return true;
    }

    // Известные IP-логгеры, request-capture сервисы и DNS/webhook collectors.
    // Сопоставление по части hostname покрывает зеркала и поддомены.
    const BLOCKED_MARKERS: &[&str] = &[
        "iplogger",
        "iplog.co",
        "2no.co",
        "yip.su",
        "grabify",
        "webhook.site",
        "requestbin",
        "requestcatcher",
        "burpcollaborator",
        "interactsh",
        "oast.",
        "canarytokens",
        "dnslog",
        "ceye.io",
    ];
    BLOCKED_MARKERS.iter().any(|marker| host.contains(marker))
}

#[cfg(test)]
fn is_loopback_test_url(raw: &str) -> bool {
    let Ok(url) = Url::parse(raw.trim()) else {
        return false;
    };
    let Ok(host) = normalized_host(&url) else {
        return false;
    };
    host.parse::<IpAddr>().is_ok_and(|ip| ip.is_loopback())
}

fn is_blocked_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ip) => is_blocked_ipv4(ip),
        IpAddr::V6(ip) => is_blocked_ipv6(ip),
    }
}

fn is_blocked_ipv4(ip: Ipv4Addr) -> bool {
    let octets = ip.octets();
    ip.is_loopback()
        || ip.is_unspecified()
        || ip.is_multicast()
        || octets[0] == 0
        || octets[0] == 10
        || (octets[0] == 100 && (64..=127).contains(&octets[1]))
        || (octets[0] == 169 && octets[1] == 254)
        || (octets[0] == 172 && (16..=31).contains(&octets[1]))
        || (octets[0] == 192 && octets[1] == 0 && octets[2] == 0)
        || (octets[0] == 192 && octets[1] == 0 && octets[2] == 2)
        || (octets[0] == 192 && octets[1] == 168)
        || (octets[0] == 198 && (18..=19).contains(&octets[1]))
        || (octets[0] == 198 && octets[1] == 51 && octets[2] == 100)
        || (octets[0] == 203 && octets[1] == 0 && octets[2] == 113)
        || octets[0] >= 224
}

fn is_blocked_ipv6(ip: Ipv6Addr) -> bool {
    let segments = ip.segments();
    ip.is_loopback()
        || ip.is_unspecified()
        || ip.is_multicast()
        || (segments[0] & 0xfe00) == 0xfc00 // unique local (fc00::/7)
        || (segments[0] & 0xffc0) == 0xfe80 // link local (fe80::/10)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_known_ip_logger_domains() {
        assert!(check_url("https://example.iplogger.org/a").is_err());
        assert!(check_url("https://grabify.link/abc").is_err());
        assert!(check_url("https://webhook.site/abc").is_err());
        assert!(check_url("https://collector.oast.example/abc").is_err());
    }

    #[test]
    fn blocks_private_reserved_and_metadata_addresses() {
        for url in [
            "http://127.0.0.1:8080/",
            "http://0.0.0.0/",
            "http://10.0.0.2/",
            "http://192.0.2.10/",
            "http://192.168.1.10/",
            "http://169.254.169.254/latest/meta-data/",
            "http://[::1]/",
            "http://[fc00::1]/",
            "http://metadata.google.internal/",
            "http://localhost./",
        ] {
            assert!(check_url(url).is_err(), "must block {url}");
        }
    }

    #[test]
    fn allows_regular_https_url_and_trailing_dot() {
        assert!(check_url("https://api.example.com/v1/ping").is_ok());
        assert!(check_url("https://example.com./health").is_ok());
    }

    #[test]
    fn blocks_non_http_schemes_and_credentials() {
        for url in [
            "javascript:alert(1)",
            "file:///etc/passwd",
            "https://user:pass@example.com/",
            "https://example.com@127.0.0.1/",
        ] {
            assert!(check_url(url).is_err(), "must block {url}");
        }
    }

    #[test]
    fn rejects_urls_without_host() {
        assert!(check_url("https:/path").is_err());
        assert!(check_url("https://").is_err());
        assert!(check_url("   ").is_err());
    }
}
