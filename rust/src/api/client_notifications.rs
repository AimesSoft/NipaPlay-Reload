use crate::frb_generated::StreamSink;

#[derive(Clone)]
pub struct ClientNotification {
    pub title: String,
    pub message: String,
}

pub fn subscribe_client_notifications(sink: StreamSink<ClientNotification>) {
    crate::client_notification_state::subscribe(sink);
}

pub fn notify_client(notification: ClientNotification) {
    crate::client_notification_state::notify(notification);
}
