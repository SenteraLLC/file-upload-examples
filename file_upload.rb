# frozen_string_literal: true

require 'net/http'
require 'json'
require 'digest'

# ================================================================
# A Ruby example that demonstrates the workflow for uploading a
# file to Sentera's cloud storage and then using the file with
# Sentera's GraphQL API to associate it with a resource such as a
# field, survey, feature set, etc.
#
# Full documentation of this workflow can be found here:
# https://api.sentera.com/api/getting_started/uploading_files.html
#
# Contact support@sentera.com with any questions.
# ================================================================

GQL_ENDPOINT = 'https://api.sentera.com/graphql'

AUTH_TOKEN_FILENAME = 'auth_token.txt' # Add your API auth token to this file

def load_auth_token
  unless File.exist?(AUTH_TOKEN_FILENAME)
    raise <<~ERROR
      #{AUTH_TOKEN_FILENAME} does not exist.
      Copy #{AUTH_TOKEN_FILENAME}.example to #{AUTH_TOKEN_FILENAME},
      replace the placeholder with your auth token, and then run again.
    ERROR
  end

  File.read(AUTH_TOKEN_FILENAME)
end

# See https://api.sentera.com/api/getting_started/authentication_and_authorization.html
# for details on how to obtain an auth token to use with Sentera's GraphQL API
AUTH_TOKEN = load_auth_token

def prepare_file_upload(file_path, content_type)
  #
  # This method demonstrates how to use the create_file_upload
  # mutation in Sentera's GraphQL API to prepare a file for
  # upload to Sentera's cloud storage.
  #
  uri = URI(GQL_ENDPOINT)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = GQL_ENDPOINT.include?('https://')
  headers = {
    'Content-Type': 'application/json',
    'Authorization': "Bearer #{AUTH_TOKEN}"
  }
  request = Net::HTTP::Post.new(uri.path, headers)

  filename = File.basename(file_path)
  byte_size = File.size(file_path)
  checksum = Digest::MD5.base64digest(File.read(file_path))

  gql = <<~GQL
    mutation CreateFileUploadDemo {
      create_file_upload (
        filename: "#{filename}"
        content_type: "#{content_type}"
        byte_size: #{byte_size}
        checksum: "#{checksum}"
      ) {
        id
        url
        headers
      }
    }
  GQL
  request.body = { 'query': gql }.to_json
  response = http.request(request)
  puts "create_file_upload response.code = #{response.code}"
  puts "create_file_upload response.body = #{response.body}"

  json = JSON.parse(response.body)
  json.dig('data', 'create_file_upload')
end

def upload_file(url, headers, file_path)
  #
  # This method demonstrates how to upload a file to
  # Sentera's cloud storage using the URL and headers
  # that were retrieved via the create_file_upload
  # GraphQL mutation.
  #
  uri = URI(url)
  file_contents = File.read(file_path)
  Net::HTTP.start(uri.host) do |http|
    response = http.send_request('PUT',
                                 uri,
                                 file_contents,
                                 headers)
    puts "upload_file response.code = #{response.code}"
  end
end

def use_file(file_id)
  #
  # This method demonstrates how to use the ID of a file that
  # was previously uploaded to Sentera's cloud storage with one
  # of the mutations in Sentera's GraphQL API that accepts a
  # file ID as an input. In this example, we'll use the
  # import_files GraphQL mutation, and attach the file to
  # a feature set that the caller is permitted to access.
  #
  uri = URI(GQL_ENDPOINT)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = GQL_ENDPOINT.include?('https://')
  headers = {
    'Content-Type': 'application/json',
    'Authorization': "Bearer #{AUTH_TOKEN}"
  }
  request = Net::HTTP::Post.new(uri.path, headers)

  owner_sentera_id = '<Your feature set ID goes here>'

  gql = <<~GQL
    mutation UseFileDemo {
      import_files (
        owner_type: FEATURE_SET
        owner_sentera_id: "#{owner_sentera_id}"
        file_type: FLIGHT_LOG
        file_keys: ["#{file_id}"]
      ) {
        status
      }
    }
  GQL
  request.body = { 'query': gql }.to_json
  response = http.request(request)
  puts "use_file response.code = #{response.code}"
  puts "use_file response.body = #{response.body}"

  json = JSON.parse(response.body)
  json.dig('data', 'import_files')
end

# -------------------------------------------------------------
# MAIN

file_path = 'example_flight_log.json'
content_type = 'application/json'

# Step 1: Prepare to upload a file
prepared_upload_json = prepare_file_upload(file_path, content_type)

# Step 2: Upload the file
upload_url = prepared_upload_json['url']
upload_headers = prepared_upload_json['headers']
upload_file(upload_url, upload_headers, file_path)

# Step 3: Use the file with Sentera FieldAgent
file_id = prepared_upload_json['id']
use_file(file_id)

puts 'Done!'
