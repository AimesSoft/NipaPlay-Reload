use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;

/// Stable control-plane error codes.
///
/// Clients branch on `error`; `errorMessage` is human-facing and may change.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorCode {
    MissingToken,
    InvalidToken,
    UpstreamUnavailable,
    InvalidInput,
    InputTooLarge,
    DeviceNotFound,
    DeviceRevoked,
    DeviceConflict,
    RateLimited,
    Internal,
}

impl ErrorCode {
    pub fn as_str(self) -> &'static str {
        match self {
            ErrorCode::MissingToken => "missing_token",
            ErrorCode::InvalidToken => "invalid_token",
            ErrorCode::UpstreamUnavailable => "upstream_unavailable",
            ErrorCode::InvalidInput => "invalid_input",
            ErrorCode::InputTooLarge => "invalid_input",
            ErrorCode::DeviceNotFound => "device_not_found",
            ErrorCode::DeviceRevoked => "device_revoked",
            ErrorCode::DeviceConflict => "device_conflict",
            ErrorCode::RateLimited => "rate_limited",
            ErrorCode::Internal => "internal_error",
        }
    }

    pub fn status(self) -> StatusCode {
        match self {
            ErrorCode::MissingToken | ErrorCode::InvalidToken => StatusCode::UNAUTHORIZED,
            ErrorCode::UpstreamUnavailable => StatusCode::SERVICE_UNAVAILABLE,
            ErrorCode::InvalidInput => StatusCode::BAD_REQUEST,
            ErrorCode::InputTooLarge => StatusCode::PAYLOAD_TOO_LARGE,
            ErrorCode::DeviceNotFound => StatusCode::NOT_FOUND,
            ErrorCode::DeviceRevoked | ErrorCode::DeviceConflict => StatusCode::FORBIDDEN,
            ErrorCode::RateLimited => StatusCode::TOO_MANY_REQUESTS,
            ErrorCode::Internal => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }
}

#[derive(Debug)]
pub struct ApiError {
    pub code: ErrorCode,
    pub message: String,
}

impl ApiError {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    pub fn internal(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::Internal, message)
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let status = self.code.status();
        let message = match self.code {
            ErrorCode::Internal => "服务内部错误，请稍后再试".to_owned(),
            ErrorCode::UpstreamUnavailable => "暂时无法核实账号，请稍后再试".to_owned(),
            _ => self.message,
        };
        (
            status,
            Json(json!({
                "success": false,
                "error": self.code.as_str(),
                "errorCode": status.as_u16(),
                "errorMessage": message,
            })),
        )
            .into_response()
    }
}
