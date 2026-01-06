const WebSocket = require('ws');

// Connect to the WebSocket endpoint
// Note: using wss:// since skywire.social handles SSL
const ws = new WebSocket('wss://skywire.social/socket/websocket');

ws.on('open', function open() {
  console.log('Connected to Skywire...');

  // Phoenix Protocol: [JoinRef, Ref, Topic, Event, Payload]
  // Join the "link_events" channel
  const joinMsg = ["1", "1", "link_events", "phx_join", {}];
  ws.send(JSON.stringify(joinMsg));

  // Send a heartbeat every 30 seconds to keep the connection alive
  setInterval(() => {
    const heartbeat = [null, "heartbeat", "phoenix", "heartbeat", {}];
    ws.send(JSON.stringify(heartbeat));
  }, 30000);
});

ws.on('message', function incoming(data) {
  const msg = JSON.parse(data);
  const topic = msg[2];
  const event = msg[3];
  const payload = msg[4];

  if (event === "phx_reply" && payload.status === "ok") {
    console.log(`Successfully joined topic: ${topic}`);
  } else if (event === "new_link") {
    console.log('---------------------------------------------------');
    console.log('🔗 NEW LINK DETECTED');
    console.log(`Event ID: ${payload.event_id}`);
    console.log('URLs:', payload.urls);
    console.log('Raw Event:', JSON.stringify(payload.raw, null, 2));
  } else {
    // console.log('Received:', msg);
  }
});

ws.on('error', function error(err) {
  console.error('WebSocket Error:', err);
});

ws.on('close', function close() {
  console.log('Disconnected.');
});
