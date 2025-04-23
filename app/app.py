import os
import json
import uuid
import logging
from datetime import datetime

from flask import Flask, request, jsonify
import psycopg2
from psycopg2.extras import RealDictCursor
from google.cloud import secretmanager
from google.cloud import pubsub_v1
import requests


app = Flask(__name__)

CONFIG_ENV = os.getenv('CONFIG_ENV', 'development')
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
DB_SECRET_NAME = os.getenv('DB_SECRET_NAME', '')
PUBSUB_TOPIC = os.getenv('PUBSUB_TOPIC', '')
LOGSTASH_HOST = os.getenv('LOGSTASH_HOST', '')
GOOGLE_CLOUD_PROJECT = os.getenv('GOOGLE_CLOUD_PROJECT', '')


logging_level = getattr(logging, LOG_LEVEL.upper())
logging.basicConfig(
    level=logging_level,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('app-service')

# Initialize clients
secret_client = secretmanager.SecretManagerServiceClient()
publisher = pubsub_v1.PublisherClient()

# Database connection
db_conn = None
db_cursor = None

def get_secret(secret_name):
    """Get secret from Google Secret Manager."""
    try:
        name = f"projects/{GOOGLE_CLOUD_PROJECT}/secrets/{secret_name}/versions/latest"
        response = secret_client.access_secret_version(request={"name": name})
        return response.payload.data.decode('UTF-8')
    except Exception as e:
        logger.error(f"Error accessing secret {secret_name}: {str(e)}")
        raise

def initialize_db_connection():
    """Initialize the database connection."""
    global db_conn, db_cursor
    
    try:
        if not DB_SECRET_NAME:
            raise ValueError("DB_SECRET_NAME environment variable is not set")
        
        connection_string = get_secret(DB_SECRET_NAME)
        
        # Connect to the database
        db_conn = psycopg2.connect(connection_string)
        db_conn.autocommit = True
        db_cursor = db_conn.cursor(cursor_factory=RealDictCursor)
        
        logger.info("Database connection established successfully")
        
        # Create table if it doesn't exist
        db_cursor.execute('''
            CREATE TABLE IF NOT EXISTS app_events (
                id SERIAL PRIMARY KEY,
                event_id VARCHAR(36) NOT NULL,
                message TEXT NOT NULL,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        return True
    except Exception as e:
        logger.error(f"Failed to initialize database connection: {str(e)}")
        return False

def send_to_logstash(log_message):
    """Send logs to Logstash."""
    if not LOGSTASH_HOST:
        logger.warning("LOGSTASH_HOST not set, skipping log forwarding")
        return
    
    try:
        requests.post(
            LOGSTASH_HOST,
            json=log_message,
            headers={"Content-Type": "application/json"}
        )
    except Exception as e:
        logger.error(f"Failed to send logs to Logstash: {str(e)}")

def publish_to_pubsub(topic_name, message):
    """Publish message to Pub/Sub."""
    if not topic_name:
        logger.warning("PUBSUB_TOPIC not set, skipping message publishing")
        return
    
    try:
        topic_path = publisher.topic_path(GOOGLE_CLOUD_PROJECT, topic_name)
        message_json = json.dumps(message).encode('utf-8')
        future = publisher.publish(topic_path, data=message_json)
        message_id = future.result()
        logger.info(f"Message {message_id} published to {topic_name}")
        return message_id
    except Exception as e:
        logger.error(f"Failed to publish message to {topic_name}: {str(e)}")
        raise

def save_to_database(event_id, message):
    """Save event to database."""
    global db_cursor
    
    if not db_cursor:
        raise ValueError("Database connection not initialized")
    
    try:
        db_cursor.execute(
            "INSERT INTO app_events (event_id, message) VALUES (%s, %s) RETURNING id",
            (event_id, message)
        )
        result = db_cursor.fetchone()
        
        logger.info(f"Event saved to database with ID: {result['id']}")
        return result['id']
    except Exception as e:
        logger.error(f"Failed to save event to database: {str(e)}")
        raise

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint."""
    logger.info("Health check requested")
    
    db_status = 'unknown'
    
    if db_conn and db_cursor:
        try:
            db_cursor.execute('SELECT 1')
            db_status = 'up'
        except Exception as e:
            db_status = 'down'
            logger.error(f"Database health check failed: {str(e)}")
    else:
        db_status = 'not_initialized'
    
    health_status = {
        'status': 'ok',
        'timestamp': datetime.now().isoformat(),
        'environment': CONFIG_ENV,
        'database': db_status,
        'version': os.getenv('APP_VERSION', '1.0.0'),
    }
    
    # Send health status to Logstash
    send_to_logstash({
        'type': 'health_check',
        'data': health_status,
        'timestamp': datetime.now().isoformat()
    })
    
    return jsonify(health_status)

@app.route('/api/events', methods=['POST'])
def create_event():
    """Create event endpoint."""
    try:
        data = request.get_json()
        
        if not data or 'message' not in data:
            return jsonify({'error': 'Message is required'}), 400
        
        message = data['message']
        event_id = str(uuid.uuid4())
        timestamp = datetime.now().isoformat()
        
        # Log the event
        logger.info(f"Processing new event: {event_id}", extra={
            'eventId': event_id,
            'message': message,
            'timestamp': timestamp
        })
        
        # Create the event object
        event = {
            'id': event_id,
            'message': message,
            'timestamp': timestamp,
            'environment': CONFIG_ENV
        }

        db_id = save_to_database(event_id, message)
        
        # Publish to Pub/Sub
        message_id = publish_to_pubsub(PUBSUB_TOPIC, event)
        
        # Send to Logstash
        send_to_logstash({
            'type': 'event_created',
            'data': event,
            'dbId': db_id,
            'pubsubMessageId': message_id
        })
        
        return jsonify({
            'id': event_id,
            'message': message,
            'timestamp': timestamp,
            'status': 'created'
        }), 201
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}", exc_info=True)
        
        # Send error to Logstash
        send_to_logstash({
            'type': 'error',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        })
        
        return jsonify({'error': 'Failed to process event'}), 500

@app.route('/api/events', methods=['GET'])
def get_events():
    """Get all events endpoint."""
    try:
        if not db_cursor:
            return jsonify({'error': 'Database connection not initialized'}), 503
        
        db_cursor.execute('SELECT * FROM app_events ORDER BY created_at DESC LIMIT 100')
        events = db_cursor.fetchall()
        
        logger.info(f"Retrieved {len(events)} events")
        
        # Send to Logstash
        send_to_logstash({
            'type': 'events_retrieved',
            'count': len(events),
            'timestamp': datetime.now().isoformat()
        })
        
        # Convert decimal types to string for JSON serialization
        events_list = [dict(event) for event in events]
        
        return jsonify(events_list)
    except Exception as e:
        logger.error(f"Error retrieving events: {str(e)}")
        
        # Send error to Logstash
        send_to_logstash({
            'type': 'error',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        })
        
        return jsonify({'error': 'Failed to retrieve events'}), 500

def start_app():
    """Start the application."""
    try:
        # Initialize database connection
        db_initialized = initialize_db_connection()
        
        if not db_initialized:
            logger.warning("Starting application without database connection. Some features may not work.")
        
        # Send startup log to Logstash
        send_to_logstash({
            'type': 'app_startup',
            'timestamp': datetime.now().isoformat(),
            'environment': CONFIG_ENV,
            'port': os.getenv('PORT', '8080'),
            'dbConnected': db_initialized
        })
        
        return True
    except Exception as e:
        logger.error(f"Failed to start application: {str(e)}", exc_info=True)
        return False

# Initialize the application on startup
start_app()

if __name__ == '__main__':
    port = int(os.getenv('PORT', '8080'))
    app.run(host='0.0.0.0', port=port)
