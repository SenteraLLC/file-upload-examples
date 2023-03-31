#!/usr/bin/env ruby

# frozen_string_literal: true

# ==================================================================
# A Ruby example that demonstrates the workflow for uploading a file
# to Sentera's cloud storage using a single PUT operation, and then
# attaching the file to something like a field, survey, feature set,
# mosaic, etc.
#
# Full documentation of this workflow can be found here:
# https://api.sentera.com/api/getting_started/uploading_files.html
#
# Contact support@sentera.com with any questions.
# ==================================================================

require 'net/http'
require 'json'
require 'digest'
require './utils'

# If you want to debug this script, run the following gem install
# commands. Then uncomment the require statements below, and put
# debugger statements in the code to trace the code execution.
#
# > gem install pry
# > gem install pry-byebug
#
# require 'pry'
# require 'pry-byebug'

#
# This method demonstrates how to use the create_file_upload
# mutation in Sentera's GraphQL API to prepare a file for
# upload to Sentera's cloud storage.
#
# @param [string] file_path Fully qualified path to file to upload
# @param [string] content_type MIME content type of the file
#
# @return [Hash] Hash containing results of the GraphQL request
#
def create_file_upload(file_path, content_type)
  puts 'Create file upload'

  filename = File.basename(file_path)
  byte_size = File.size(file_path)
  checksum = Digest::MD5.base64digest(File.read(file_path))

  gql = <<~GQL
    mutation CreateFileUpload(
      $byte_size: BigInt!
      $checksum: String!
      $content_type: String!
      $filename: String!
    ) {
      create_file_upload(
        filename: $filename
        content_type: $content_type
        byte_size: $byte_size
        checksum: $checksum
      ) {
        id
        url
        headers
      }
    }
  GQL

  variables = {
    byte_size: byte_size,
    checksum: checksum,
    content_type: content_type,
    filename: filename
  }

  response = make_graphql_request(gql, variables)
  json = JSON.parse(response.body)
  json.dig('data', 'create_file_upload')
end

#
# This method demonstrates how to upload a file to
# Sentera's cloud storage using the URL and headers
# that were retrieved via the create_file_upload
# GraphQL mutation.
#
# @param [string] url Pre-signed URL used to upload the file
# @param [Hash] headers Hash of headers used on the request to
#                       PUT the file to the specified URL
# @param [string] file_path Fully qualified path to file to upload
#
# @return [void]
#
def upload_file(url, headers, file_path)
  puts 'Upload file'

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

#
# This method demonstrates how to use the ID of a file that
# was previously uploaded to Sentera's cloud storage with one
# of the mutations in Sentera's GraphQL API that accepts a
# file ID as an input. In this example, we'll use the
# import_files GraphQL mutation, and attach the file to
# a file owner that belongs to the caller's FieldAgent organization.
#
# @param [string] file_id ID of the uploaded file
# @param [string] file_owner_type Type of file owner to create. For example,
#                                 FEATURE_SET, MOSAIC, etc.
# @param [string] file_owner_sentera_id Sentera ID of the resource
#                                       (field, survey, feature set, etc.)
#                                       to which the file should be attached.
#
# @return [Hash] Hash containing results of the GraphQL request
#
def use_file(file_id, file_owner_type, file_owner_sentera_id)
  puts 'Use file'

  gql = <<~GQL
    mutation ImportFiles(
      $file_keys: [String!]!
      $file_type: FileType!
      $owner_sentera_id: ID!
      $owner_type: FileOwnerType!
    ) {
      import_files(
        owner_type: $owner_type
        owner_sentera_id: $owner_sentera_id
        file_type: $file_type
        file_keys: $file_keys
      ) {
        status
      }
    }
  GQL

  variables = {
    owner_type: file_owner_type,
    owner_sentera_id: file_owner_sentera_id,
    file_type: 'FLIGHT_LOG',
    file_keys: [file_id]
  }

  response = make_graphql_request(gql, variables)
  json = JSON.parse(response.body)
  json.dig('data', 'import_files')
end

# MAIN

# **************************************************
# Set these variables based on the file you want to
# upload and the resource within FieldAgent to which
# you wish to attach the file.
file_path = 'test.geojson' # Your fully qualified file path goes here
content_type = 'application/json' # Your MIME content type goes here
file_owner_type = 'FEATURE_SET' # Your file owner type goes here
file_owner_sentera_id = 'sezjmpa_FS_arpmAcmeOrg_CV_deve_b822f1701_230330_110124' # Your file owner Sentera ID goes here
# **************************************************

# Step 1: Create a file upload
results = create_file_upload(file_path, content_type)
upload_url = results['url']
upload_headers = results['headers']
file_id = results['id']

# Step 2: Upload the file
upload_file(upload_url, upload_headers, file_path)

# Step 3: Use the file with FieldAgent
results = use_file(file_id, file_owner_type, file_owner_sentera_id)

if results
  puts "Done! File #{file_path} was successfully uploaded and attached to #{file_owner_type} #{file_owner_sentera_id}."
else
  puts 'Failed'
end
