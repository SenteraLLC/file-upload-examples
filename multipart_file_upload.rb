# frozen_string_literal: true

# ==================================================================
# A Ruby example that demonstrates the workflow for uploading a file
# to Sentera's cloud storage using a multipart upload, and then
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
# This method demonstrates how to use the create_multipart_file_upload
# mutation in Sentera's GraphQL API to initiate a multipart file
# upload with Sentera's cloud storage.
#
# @param [string] file_path Fully qualified path to file to upload
# @param [string] content_type MIME content type of the file
# @param [string] parent_sentera_id Sentera ID of the parent resource
#                                   within FieldAgent that a file owner
#                                   will be created within. For example,
#                                   the parent could be a survey, and
#                                   the file owner is a mosaic created
#                                   within that survey.
# @param [string] file_owner_type Type of file owner to create. For example,
#                                 FEATURE_SET, MOSAIC, etc.
#
# @return [Hash] Hash containing results of the GraphQL request
#
def create_multipart_file_upload(file_path, content_type, parent_sentera_id, file_owner_type)
  puts 'Create a multipart file upload'

  filename = File.basename(file_path)
  byte_size = File.size(file_path)

  gql = <<~GQL
    mutation CreateMultipartFileUpload {
      create_multipart_file_upload (
        byte_size: #{byte_size}
        content_type: "#{content_type}"
        filename: "#{filename}"
        file_upload_owner: {
          parent_sentera_id: "#{parent_sentera_id}"
          owner_type: #{file_owner_type}
        }
      ) {
        file_id
        owner_sentera_id
        s3_key
        upload_id
      }
    }
  GQL

  response = make_graphql_request(gql)
  json = JSON.parse(response.body)
  json.dig('data', 'create_multipart_file_upload')
end

#
# This method demonstrates how to upload a file to
# Sentera's cloud storage using an upload_id and
# s3_key that were retrieved via the create_multipart_file_upload
# GraphQL mutation.
#
# See https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpu-upload-object.html
# for more details.
#
# @param [string] file_path Fully qualified path to file to upload
# @param [string] s3_key S3 key of the file
# @param [string] upload_id ID of the upload
#
# @return [Array<Hash>] Array of hash objects containing a part number and an etag
#
def upload_file(file_path, s3_key, upload_id)
  puts 'Upload file'

  parts = []

  # Compute the number of parts based on 5MB chunks
  file_size_bytes = File.size(file_path)
  part_size_bytes = 5 * 1024 * 1024 # 5 megabytes is the smaller part size AWS S3 permits
  num_parts = file_size_bytes / part_size_bytes
  remainder = file_size_bytes % part_size_bytes
  num_parts += 1 if remainder > 0

  part_number = 1
  read_bytes = 0

  # Read the file a chunk at a time and write the chunk to S3
  File.open(file_path) do |file|
    until file.eof?
      remaining_bytes = file_size_bytes - read_bytes
      buffer_size = if remaining_bytes < part_size_bytes
                      remaining_bytes
                    else
                      part_size_bytes
                    end
      buffer = file.read(buffer_size)

      url = prepare_file_part(part_number, s3_key, upload_id)

      uri = URI(url)
      Net::HTTP.start(uri.host) do |http|
        response = http.send_request('PUT', uri, buffer)
        puts "upload part #{part_number} response.code = #{response.code}"

        # For production use you would add appropriate
        # error handling here, such as retrying the upload
        raise "Error reading part #{part_number}, response code: #{response.code}" unless response.code == '200'

        # eTags are required to be wrapped in double quotes
        # (https://www.rfc-editor.org/rfc/rfc2616#section-14.19),
        # but we don't want these because they'll mess up the
        # GraphQL query we'll issue later on, so remove them
        etag = response.header['etag']
        etag = etag[1, etag.length - 2]

        part = {
          part_number: part_number,
          etag: etag
        }
        parts.push(part)
      end

      part_number += 1
      read_bytes += buffer_size
    end
  end

  parts
end

#
# This method demonstrates how to get a pre-signed URL
# to upload a specific part of a file.
#
# @param [string] part_number Part number between 1 and 10,000
# @param [string] s3_key S3 key of the file
# @param [string] upload_id ID of the upload
#
# @return [string] Pre-signed URL for the part
#
def prepare_file_part(part_number, s3_key, upload_id)
  gql = <<~GQL
    mutation PrepareMultipartFileUploadPart {
      prepare_multipart_file_upload_part (
        part_number: #{part_number}
        s3_key: "#{s3_key}"
        upload_id: "#{upload_id}"
      ) {
        url
      }
    }
  GQL

  response = make_graphql_request(gql)
  json = JSON.parse(response.body)
  results = json.dig('data', 'prepare_multipart_file_upload_part')
  results['url']
end

#
# This methods demonstrates how to complete a multipart
# file upload. You need to provide the upload ID, the S3 key,
# a list of parts (part number and e-tag).
#
# @param [<Array<Hash>>] parts Array of part information
# @param [string] s3_key S3 key of the file
# @param [string] upload_id ID of the upload
#
# @return [Boolean] True if request was successful
#
def complete_multipart_file_upload(parts, s3_key, upload_id)
  puts 'Complete multipart file upload'

  parts_gql = '[' + parts.reduce("") do |memo, part|
    memo += %Q|{part_number: #{part[:part_number]}, etag: "#{part[:etag]}"}|
    memo
  end + ']'

  gql = <<~GQL
    mutation CompleteMultipartFileUpload {
      complete_multipart_file_upload (
        parts: #{parts_gql}
        s3_key: "#{s3_key}"
        upload_id: "#{upload_id}"
      )
    }
  GQL

  response = make_graphql_request(gql)
  json = JSON.parse(response.body)
  json.dig('data', 'complete_multipart_file_upload')
end

#
# This method demonstrates how to use the ID of a file that
# was previously uploaded to Sentera's cloud storage with one
# of the mutations in Sentera's GraphQL API that accepts a
# file ID as an input. In this example, we'll use the
# import_files GraphQL mutation, and attach the file to
# a feature set that the caller is permitted to access.
#
# @param [string] file_id ID of the uploaded file
# @param [string] file_owner_type Type of file owner to create. For example,
#                                 FEATURE_SET, MOSAIC, etc.
# @param [string] file_owner_sentera_id Sentera ID of the resource
#                                       (field, survey, feature set, etc.)
#                                       to which the file should be attached.
# @param [string] file_path Fully qualified path to file that was uploaded
#
# @return [Hash] Hash containing results of the GraphQL request
#
def use_file(file_id, file_owner_type, file_owner_sentera_id, file_path)
  puts 'Use file'

  path = File.dirname(file_path)
  filename = File.basename(file_path)
  byte_size = File.size(file_path)

  gql = <<~GQL
    mutation UpsertFiles {
      upsert_files (
        owner: {
          owner_type: #{file_owner_type}
          sentera_id: "#{file_owner_sentera_id}"
        }
        files: [
          {
            file_type: #{file_owner_type}
            filename: "#{filename}"
            path: "#{path}"
            size: #{byte_size}
            version: 1
          }
        ]
      ) {
        succeeded {
          sentera_id
        }
      }
    }
  GQL
  response = make_graphql_request(gql)
  json = JSON.parse(response.body)
  json.dig('data', 'upsert_files')
end

# MAIN

# **************************************************
# Set these variables based on the file you want to
# upload and the resource within FieldAgent to which
# you wish to attach the file.
file_path = 'test.tif' # Your fully qualified file path goes here
content_type = 'image/tiff' # Your MIME content type goes here'
parent_sentera_id = 'llzwked_CO_arpmAcmeOrg_CV_deve_b822f1701_230330_110124' # Your parent Sentera ID goes here
file_owner_type = 'MOSAIC' # Your file owner type goes here
# **************************************************

# Step 1: Create a multipart file upload
results = create_multipart_file_upload(file_path, content_type, parent_sentera_id, file_owner_type)
if results.nil?
  puts 'Failed'
  exit
end
file_id = results['file_id']
file_owner_sentera_id = results['owner_sentera_id']
s3_key = results['s3_key']
upload_id = results['upload_id']

# Step 2: Upload the file in parts
parts = upload_file(file_path, s3_key, upload_id)

# Step 3: Complete the multipart file upload
complete_multipart_file_upload(parts, s3_key, upload_id)

# Step 4: Use the file with Sentera FieldAgent
results = use_file(file_id, file_owner_type, file_owner_sentera_id, file_path)

if results
  puts "Done! File #{file_path} was successfully uploaded and attached to #{file_owner_type} #{file_owner_sentera_id}."
else
  puts 'Failed'
end
