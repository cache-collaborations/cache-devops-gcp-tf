import json
import unittest
from unittest.mock import patch, MagicMock

import app


class TestApp(unittest.TestCase):
    def setUp(self):
        app.app.testing = True
        self.client = app.app.test_client()

    @patch('app.send_to_logstash')
    def test_health_check(self, mock_send_to_logstash):
        """Test health check endpoint."""
        # Mock the database connection and cursor
        app.db_conn = MagicMock()
        app.db_cursor = MagicMock()
        app.db_cursor.execute.return_value = None
        
        response = self.client.get('/health')
        data = json.loads(response.data)
        
        self.assertEqual(response.status_code, 200)
        self.assertEqual(data['status'], 'ok')
        self.assertEqual(data['database'], 'up')
        
        # Verify logstash was called
        mock_send_to_logstash.assert_called_once()

    @patch('app.send_to_logstash')
    @patch('app.publish_to_pubsub')
    @patch('app.save_to_database')
    def test_create_event(self, mock_save_to_db, mock_publish, mock_send_to_logstash):
        """Test create event endpoint."""
        # Set up mocks
        mock_save_to_db.return_value = 1
        mock_publish.return_value = "message-id-123"
        
        # Test with valid payload
        response = self.client.post(
            '/api/events',
            data=json.dumps({'message': 'Test message'}),
            content_type='application/json'
        )
        data = json.loads(response.data)
        
        self.assertEqual(response.status_code, 201)
        self.assertIn('id', data)
        self.assertEqual(data['message'], 'Test message')
        self.assertEqual(data['status'], 'created')
        
        # Verify mocks were called
        mock_save_to_db.assert_called_once()
        mock_publish.assert_called_once()
        mock_send_to_logstash.assert_called()

    @patch('app.send_to_logstash')
    def test_create_event_missing_message(self, mock_send_to_logstash):
        """Test create event with missing message."""
        response = self.client.post(
            '/api/events',
            data=json.dumps({}),
            content_type='application/json'
        )
        data = json.loads(response.data)
        
        self.assertEqual(response.status_code, 400)
        self.assertEqual(data['error'], 'Message is required')

    @patch('app.send_to_logstash')
    def test_get_events(self, mock_send_to_logstash):
        """Test get events endpoint."""
        # Mock database cursor
        app.db_cursor = MagicMock()
        app.db_cursor.fetchall.return_value = [
            {
                'id': 1,
                'event_id': '123e4567-e89b-12d3-a456-426614174000',
                'message': 'Test message',
                'created_at': '2023-06-01T12:00:00Z'
            }
        ]
        
        response = self.client.get('/api/events')
        data = json.loads(response.data)
        
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]['event_id'], '123e4567-e89b-12d3-a456-426614174000')
        
        # Verify logstash was called
        mock_send_to_logstash.assert_called()

    @patch('app.send_to_logstash')
    def test_get_events_no_db_connection(self, mock_send_to_logstash):
        """Test get events with no database connection."""
        # Set db_cursor to None to simulate no connection
        app.db_cursor = None
        
        response = self.client.get('/api/events')
        data = json.loads(response.data)
        
        self.assertEqual(response.status_code, 503)
        self.assertEqual(data['error'], 'Database connection not initialized')


class TestHelperFunctions(unittest.TestCase):
    @patch('app.secret_client')
    def test_get_secret(self, mock_secret_client):
        """Test get_secret function."""
        # Setup mock response
        mock_response = MagicMock()
        mock_response.payload.data = b'test-secret-value'
        mock_secret_client.access_secret_version.return_value = mock_response
        
        # Set project ID
        app.GOOGLE_CLOUD_PROJECT = 'test-project'
        
        # Call function
        result = app.get_secret('test-secret')
        
        # Verify result
        self.assertEqual(result, 'test-secret-value')
        mock_secret_client.access_secret_version.assert_called_once()

    @patch('app.publisher')
    def test_publish_to_pubsub(self, mock_publisher):
        """Test publish_to_pubsub function."""
        # Setup mock
        mock_future = MagicMock()
        mock_future.result.return_value = 'message-id-123'
        mock_publisher.publish.return_value = mock_future
        mock_publisher.topic_path.return_value = 'projects/test-project/topics/test-topic'
        
        # Set project ID
        app.GOOGLE_CLOUD_PROJECT = 'test-project'
        
        # Call function
        result = app.publish_to_pubsub('test-topic', {'data': 'test'})
        
        # Verify result
        self.assertEqual(result, 'message-id-123')
        mock_publisher.publish.assert_called_once()

    def test_publish_to_pubsub_empty_topic(self):
        """Test publish_to_pubsub with empty topic."""
        result = app.publish_to_pubsub('', {'data': 'test'})
        self.assertIsNone(result)

    @patch('app.db_cursor')
    def test_save_to_database(self, mock_db_cursor):
        """Test save_to_database function."""
        # Setup mock
        mock_db_cursor.fetchone.return_value = {'id': 123}
        
        # Call function
        result = app.save_to_database('event-id-123', 'Test message')
        
        # Verify result
        self.assertEqual(result, 123)
        mock_db_cursor.execute.assert_called_once()

    @patch('app.requests')
    def test_send_to_logstash(self, mock_requests):
        """Test send_to_logstash function."""
        # Set logstash host
        app.LOGSTASH_HOST = 'http://logstash:8080'
        
        # Call function
        app.send_to_logstash({'message': 'test'})
        
        # Verify requests.post was called
        mock_requests.post.assert_called_once_with(
            'http://logstash:8080',
            json={'message': 'test'},
            headers={'Content-Type': 'application/json'}
        )

    def test_send_to_logstash_no_host(self):
        """Test send_to_logstash with no host."""
        # Set logstash host to empty
        app.LOGSTASH_HOST = ''
        
        # This should not raise an exception
        app.send_to_logstash({'message': 'test'})

if __name__ == '__main__':
    unittest.main()
