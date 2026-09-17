use std::{env, net::SocketAddr, str::FromStr, time::Duration};

use thiserror::Error;

#[derive(Clone, Debug)]
pub struct Config {
    pub bind_addr: SocketAddr,
    pub database_url: String,
    pub kafka: KafkaConfig,
    pub auth: AuthConfig,
    pub alpaca: AlpacaConfig,
    pub stream: StreamConfig,
    pub retention_days: u32,
    pub allowed_origins: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct KafkaConfig {
    pub bootstrap_servers: String,
    pub transactional_id: String,
    pub group_id: String,
    pub security_protocol: String,
    pub sasl_mechanism: Option<String>,
    pub sasl_username: Option<String>,
    pub sasl_password: Option<String>,
    pub ssl_ca_location: Option<String>,
    pub aws_region: Option<String>,
}

#[derive(Clone, Debug)]
pub struct AuthConfig {
    pub issuer: String,
    pub audience: String,
    pub jwks_url: Option<String>,
    pub hs256_secret: Option<String>,
}

#[derive(Clone, Debug)]
pub struct AlpacaConfig {
    pub enabled: bool,
    pub api_key: Option<String>,
    pub secret_key: Option<String>,
    pub stock_ws_url: String,
    pub crypto_ws_url: String,
    pub symbols: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct StreamConfig {
    pub stale_after: Duration,
    pub heartbeat: Duration,
    pub buffer_capacity: usize,
    pub replay_capacity: usize,
    pub max_per_user: usize,
    pub max_global: usize,
}

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("missing required environment variable {0}")]
    Missing(&'static str),
    #[error("invalid {name}: {reason}")]
    Invalid { name: &'static str, reason: String },
    #[error("exactly one of MARKET_JWKS_URL or MARKET_JWT_HS256_SECRET must be configured")]
    AuthMode,
    #[error("ALPACA_API_KEY and ALPACA_SECRET_KEY are required when ingestion is enabled")]
    AlpacaCredentials,
}

impl Config {
    pub fn from_env() -> Result<Self, ConfigError> {
        let jwks_url = optional("MARKET_JWKS_URL");
        let hs256_secret = optional("MARKET_JWT_HS256_SECRET");
        if jwks_url.is_some() == hs256_secret.is_some() {
            return Err(ConfigError::AuthMode);
        }

        let enabled = parse("MARKET_INGESTION_ENABLED", true)?;
        let api_key = optional("ALPACA_API_KEY");
        let secret_key = optional("ALPACA_SECRET_KEY");
        if enabled && (api_key.is_none() || secret_key.is_none()) {
            return Err(ConfigError::AlpacaCredentials);
        }

        let symbols = env::var("MARKET_SYMBOLS")
            .unwrap_or_else(|_| "AAPL,BTC/USD".into())
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_owned)
            .collect::<Vec<_>>();
        if enabled && symbols.is_empty() {
            return Err(ConfigError::Invalid {
                name: "MARKET_SYMBOLS",
                reason: "at least one symbol is required".into(),
            });
        }

        Ok(Self {
            bind_addr: parse_with_default("MARKET_BIND_ADDR", "0.0.0.0:8081")?,
            database_url: required("DATABASE_URL")?,
            kafka: KafkaConfig::from_env()?,
            auth: AuthConfig {
                issuer: required("MARKET_JWT_ISSUER")?,
                audience: required("MARKET_JWT_AUDIENCE")?,
                jwks_url,
                hs256_secret,
            },
            alpaca: AlpacaConfig {
                enabled,
                api_key,
                secret_key,
                stock_ws_url: env::var("ALPACA_STOCK_WS_URL")
                    .unwrap_or_else(|_| "wss://stream.data.alpaca.markets/v2/iex".into()),
                crypto_ws_url: env::var("ALPACA_CRYPTO_WS_URL").unwrap_or_else(|_| {
                    "wss://stream.data.alpaca.markets/v1beta3/crypto/us".into()
                }),
                symbols,
            },
            stream: StreamConfig {
                stale_after: Duration::from_secs(parse("MARKET_STALE_AFTER_SECONDS", 30)?),
                heartbeat: Duration::from_secs(parse("MARKET_HEARTBEAT_SECONDS", 15)?),
                buffer_capacity: parse("MARKET_STREAM_BUFFER", 256)?,
                replay_capacity: parse("MARKET_REPLAY_BUFFER", 512)?,
                max_per_user: parse("MARKET_MAX_STREAMS_PER_USER", 5)?,
                max_global: parse("MARKET_MAX_STREAMS_GLOBAL", 2_000)?,
            },
            retention_days: parse("MARKET_RETENTION_DAYS", 90)?,
            allowed_origins: env::var("MARKET_ALLOWED_ORIGINS")
                .unwrap_or_else(|_| "http://127.0.0.1:14173".into())
                .split(',')
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_owned)
                .collect(),
        })
    }
}

impl KafkaConfig {
    pub fn from_env() -> Result<Self, ConfigError> {
        Ok(Self {
            bootstrap_servers: required("KAFKA_BOOTSTRAP_SERVERS")?,
            transactional_id: env::var("KAFKA_TRANSACTIONAL_ID")
                .unwrap_or_else(|_| "indus-market-data-producer".into()),
            group_id: env::var("KAFKA_GROUP_ID")
                .unwrap_or_else(|_| "indus-market-data-writer-v1".into()),
            security_protocol: env::var("KAFKA_SECURITY_PROTOCOL")
                .unwrap_or_else(|_| "PLAINTEXT".into()),
            sasl_mechanism: optional("KAFKA_SASL_MECHANISM"),
            sasl_username: optional("KAFKA_SASL_USERNAME"),
            sasl_password: optional("KAFKA_SASL_PASSWORD"),
            ssl_ca_location: optional("KAFKA_SSL_CA_LOCATION"),
            aws_region: optional("AWS_REGION"),
        })
    }
}

fn required(name: &'static str) -> Result<String, ConfigError> {
    optional(name).ok_or(ConfigError::Missing(name))
}

fn optional(name: &'static str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.trim().is_empty())
}

fn parse<T>(name: &'static str, default: T) -> Result<T, ConfigError>
where
    T: FromStr,
    T::Err: std::fmt::Display,
{
    match env::var(name) {
        Ok(value) => value.parse().map_err(|error: T::Err| ConfigError::Invalid {
            name,
            reason: error.to_string(),
        }),
        Err(_) => Ok(default),
    }
}

fn parse_with_default<T>(name: &'static str, default: &str) -> Result<T, ConfigError>
where
    T: FromStr,
    T::Err: std::fmt::Display,
{
    env::var(name)
        .unwrap_or_else(|_| default.to_owned())
        .parse()
        .map_err(|error: T::Err| ConfigError::Invalid {
            name,
            reason: error.to_string(),
        })
}

#[cfg(test)]
mod tests {
    use std::sync::{Mutex, MutexGuard};

    use super::*;

    static ENV_LOCK: Mutex<()> = Mutex::new(());
    const VARIABLES: &[&str] = &[
        "ALPACA_API_KEY",
        "ALPACA_CRYPTO_WS_URL",
        "ALPACA_SECRET_KEY",
        "ALPACA_STOCK_WS_URL",
        "AWS_REGION",
        "DATABASE_URL",
        "KAFKA_BOOTSTRAP_SERVERS",
        "KAFKA_GROUP_ID",
        "KAFKA_SASL_MECHANISM",
        "KAFKA_SASL_PASSWORD",
        "KAFKA_SASL_USERNAME",
        "KAFKA_SECURITY_PROTOCOL",
        "KAFKA_SSL_CA_LOCATION",
        "KAFKA_TRANSACTIONAL_ID",
        "MARKET_ALLOWED_ORIGINS",
        "MARKET_BIND_ADDR",
        "MARKET_HEARTBEAT_SECONDS",
        "MARKET_INGESTION_ENABLED",
        "MARKET_JWKS_URL",
        "MARKET_JWT_AUDIENCE",
        "MARKET_JWT_HS256_SECRET",
        "MARKET_JWT_ISSUER",
        "MARKET_MAX_STREAMS_GLOBAL",
        "MARKET_MAX_STREAMS_PER_USER",
        "MARKET_REPLAY_BUFFER",
        "MARKET_RETENTION_DAYS",
        "MARKET_STALE_AFTER_SECONDS",
        "MARKET_STREAM_BUFFER",
        "MARKET_SYMBOLS",
    ];

    struct CleanEnvironment {
        _lock: MutexGuard<'static, ()>,
    }

    impl CleanEnvironment {
        fn new() -> Self {
            let lock = ENV_LOCK.lock().expect("environment lock should be available");
            for name in VARIABLES {
                // SAFETY: every environment-mutating test in this module holds ENV_LOCK.
                unsafe { env::remove_var(name) };
            }
            Self { _lock: lock }
        }

        fn set(&self, name: &str, value: &str) {
            // SAFETY: this guard holds ENV_LOCK for its full lifetime.
            unsafe { env::set_var(name, value) };
        }
    }

    impl Drop for CleanEnvironment {
        fn drop(&mut self) {
            for name in VARIABLES {
                // SAFETY: this guard still holds ENV_LOCK while restoring the process environment.
                unsafe { env::remove_var(name) };
            }
        }
    }

    fn required_environment() -> CleanEnvironment {
        let environment = CleanEnvironment::new();
        environment.set("DATABASE_URL", "postgres://localhost/indus");
        environment.set("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092");
        environment.set("MARKET_JWT_ISSUER", "https://issuer.example");
        environment.set("MARKET_JWT_AUDIENCE", "indus-market-data");
        environment.set("MARKET_JWT_HS256_SECRET", "a-development-secret-longer-than-32-bytes");
        environment.set("MARKET_INGESTION_ENABLED", "false");
        environment
    }

    #[test]
    fn loads_safe_defaults_when_optional_settings_are_absent() {
        let _environment = required_environment();

        let config = Config::from_env().expect("the minimum complete configuration should load");

        assert_eq!(config.bind_addr, "0.0.0.0:8081".parse().unwrap());
        assert_eq!(config.kafka.transactional_id, "indus-market-data-producer");
        assert_eq!(config.kafka.group_id, "indus-market-data-writer-v1");
        assert_eq!(config.kafka.security_protocol, "PLAINTEXT");
        assert_eq!(config.alpaca.symbols, ["AAPL", "BTC/USD"]);
        assert_eq!(config.stream.stale_after, Duration::from_secs(30));
        assert_eq!(config.stream.heartbeat, Duration::from_secs(15));
        assert_eq!(config.stream.buffer_capacity, 256);
        assert_eq!(config.stream.replay_capacity, 512);
        assert_eq!(config.stream.max_per_user, 5);
        assert_eq!(config.stream.max_global, 2_000);
        assert_eq!(config.retention_days, 90);
        assert_eq!(config.allowed_origins, ["http://127.0.0.1:14173"]);
    }

    #[test]
    fn loads_explicit_transport_stream_and_provider_settings() {
        let environment = required_environment();
        environment.set("MARKET_BIND_ADDR", "127.0.0.1:9090");
        environment.set("MARKET_SYMBOLS", " MSFT, ETH/USD, ");
        environment.set("MARKET_ALLOWED_ORIGINS", "https://one.example, https://two.example");
        environment.set("MARKET_STALE_AFTER_SECONDS", "45");
        environment.set("MARKET_HEARTBEAT_SECONDS", "10");
        environment.set("MARKET_STREAM_BUFFER", "64");
        environment.set("MARKET_REPLAY_BUFFER", "128");
        environment.set("MARKET_MAX_STREAMS_PER_USER", "3");
        environment.set("MARKET_MAX_STREAMS_GLOBAL", "100");
        environment.set("MARKET_RETENTION_DAYS", "30");
        environment.set("KAFKA_SECURITY_PROTOCOL", "SASL_SSL");
        environment.set("KAFKA_SASL_MECHANISM", "AWS_MSK_IAM");
        environment.set("AWS_REGION", "us-east-1");
        environment.set("ALPACA_STOCK_WS_URL", "wss://stocks.example");
        environment.set("ALPACA_CRYPTO_WS_URL", "wss://crypto.example");

        let config = Config::from_env().expect("explicit configuration should load");

        assert_eq!(config.bind_addr, "127.0.0.1:9090".parse().unwrap());
        assert_eq!(config.alpaca.symbols, ["MSFT", "ETH/USD"]);
        assert_eq!(config.allowed_origins.len(), 2);
        assert_eq!(config.stream.stale_after, Duration::from_secs(45));
        assert_eq!(config.stream.max_global, 100);
        assert_eq!(config.retention_days, 30);
        assert_eq!(config.kafka.sasl_mechanism.as_deref(), Some("AWS_MSK_IAM"));
        assert_eq!(config.kafka.aws_region.as_deref(), Some("us-east-1"));
        assert_eq!(config.alpaca.stock_ws_url, "wss://stocks.example");
    }

    #[test]
    fn rejects_ambiguous_auth_missing_provider_credentials_and_invalid_values() {
        let environment = required_environment();
        environment.set("MARKET_JWKS_URL", "https://issuer.example/jwks.json");
        assert!(matches!(Config::from_env(), Err(ConfigError::AuthMode)));

        environment.set("MARKET_JWKS_URL", "");
        environment.set("MARKET_INGESTION_ENABLED", "true");
        assert!(matches!(Config::from_env(), Err(ConfigError::AlpacaCredentials)));

        environment.set("ALPACA_API_KEY", "key");
        environment.set("ALPACA_SECRET_KEY", "secret");
        environment.set("MARKET_SYMBOLS", " , ");
        assert!(matches!(
            Config::from_env(),
            Err(ConfigError::Invalid { name: "MARKET_SYMBOLS", .. })
        ));

        environment.set("MARKET_SYMBOLS", "AAPL");
        environment.set("MARKET_STREAM_BUFFER", "not-a-number");
        assert!(matches!(
            Config::from_env(),
            Err(ConfigError::Invalid { name: "MARKET_STREAM_BUFFER", .. })
        ));
    }

    #[test]
    fn rejects_missing_required_values_and_invalid_addresses() {
        let environment = CleanEnvironment::new();
        environment.set("MARKET_JWT_HS256_SECRET", "a-development-secret-longer-than-32-bytes");
        environment.set("MARKET_INGESTION_ENABLED", "false");
        assert!(matches!(
            Config::from_env(),
            Err(ConfigError::Missing("DATABASE_URL"))
        ));

        environment.set("DATABASE_URL", "postgres://localhost/indus");
        environment.set("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092");
        environment.set("MARKET_JWT_ISSUER", "https://issuer.example");
        environment.set("MARKET_JWT_AUDIENCE", "indus-market-data");
        environment.set("MARKET_BIND_ADDR", "invalid");
        assert!(matches!(
            Config::from_env(),
            Err(ConfigError::Invalid { name: "MARKET_BIND_ADDR", .. })
        ));
    }
}
