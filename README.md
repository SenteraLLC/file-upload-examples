# file-upload-examples
Examples in different languages that demonstrate how to upload a file to [Sentera's FieldAgent platform](https://sentera.com/fieldagent-platform/)

## Workflow
There are three basic steps for uploading a file and using it with Sentera FieldAgent:

1. **Prepare the file upload** - Request credentials for uploading a file to Sentera's cloud storage.
2. **Upload the file** - Upload a file directly to Sentera's cloud storage using a pre-signed upload URL.
3. **Use the file** - Specify the ID of the uploaded file with one of the mutations in [Sentera's GraphQL API](https://api.sentera.com/api/docs/mutation.doc.html) to attach the file to a resource such as a field, survey, feature set, etc.

Full documentation of this workflow can be found [here](https://api.sentera.com/api/getting_started/uploading_files.html)

## Examples
| Language | Run Command             |
| :------- | :-----------------------|
| Ruby     | `> ruby file_upload.rb` |
