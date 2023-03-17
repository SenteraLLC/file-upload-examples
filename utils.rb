# frozen_string_literal: true
require 'net/http'

FIELDAGENT_ACCESS_TOKEN_FILENAME = 'fieldagent_access_token.txt' # Add your FieldAgent access token to this file

GQL_ENDPOINT = 'https://api.sentera.com/graphql'

#
# Loads the access token specified in FIELDAGENT_ACCESS_TOKEN_FILENAME
#
# See https://api.sentera.com/api/getting_started/authentication_and_authorization.html
# for details on how to obtain an auth token to use with Sentera's GraphQL API
#
# @return [string] FieldAgent
#
def load_fieldagent_access_token
  unless File.exist?(FIELDAGENT_ACCESS_TOKEN_FILENAME)
    raise <<~ERROR
      #{FIELDAGENT_ACCESS_TOKEN_FILENAME} does not exist.
      Copy #{FIELDAGENT_ACCESS_TOKEN_FILENAME}.example to #{FIELDAGENT_ACCESS_TOKEN_FILENAME},
      replace the placeholder with your auth token, and then run again.
    ERROR
  end

  File.read(FIELDAGENT_ACCESS_TOKEN_FILENAME)
end

#
# Makes a request to FieldAgent's GraphQL API
#
# @param [string] access_token FieldAgent access token
# @param [string] gql GraphQL query or mutation to request
#
# @return [Net::HTTP::Response] HTTP response object
#
def make_graphql_request(access_token, gql)
  uri = URI(GQL_ENDPOINT)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = GQL_ENDPOINT.include?('https://')
  headers = {
    'Content-Type': 'application/json',
    'Authorization': "Bearer #{access_token}"
  }
  request = Net::HTTP::Post.new(uri.path, headers)
  request.body = { 'query': gql }.to_json

  puts "Make GraphQL request: gql = #{gql}"
  response = http.request(request)
  puts "GraphQL response: code = #{response.code}, body = #{response.body}"

  response
end
