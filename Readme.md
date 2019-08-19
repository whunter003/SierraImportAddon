# Sierra API Server Addon

This addon imports ILS data from Sierra's Items API for transactions that are in the specified data import queue. The transaction will be routed to one of 2 queues, depending on the success of the data import.

## Settings

### RequestMonitorQueue

The queue that the addon will monitor for transactions that need ILS data automatically imported from Sierra. The value of this setting is required.

*Default*: `Awaiting ILS Data Import`

### SuccessRouteQueue

The queue that the addon will route requests to after successfully importing ILS data from Sierra. The value of this setting is required.

*Default*: `Awaiting Request Processing`

### ErrorRouteQueue

The queue that the addon will route requests to if errors are encountered while importing ILS data from Sierra. The value of this setting is required.

*Default*: `Awaiting Manual Data Import`


### SierraApiUrl

Base URL for the Sierra API. The value of this setting is required.

### ClientKey

Client Key used for authorization for the Sierra API. The value of this setting is required.

### ClientSecret

Client Secret used for authorization for the Sierra API. The value of this setting is required.

### UserAgent

Specifies the User-Agent that is sent to Sierra with API requests. The value of this setting is optional.


### BibIdSourceField

Specifies the transaction field that contains the Sierra record's BibID. This setting will be used along with the VolumeSourceField setting to gather item data from Sierra's item API. The value of this setting is required and must match the name of a column from the Transactions table.

*Default*: `ItemInfo3`

### VolumeSourceField

Specifies the transaction field that contains the Sierra record's Volume. This setting will be used along with the BibIdSourceField setting to gather item data from Sierra's item API. The transaction field specified in this setting may contain additional information that is not related to the item's volume. The value of this setting is required and must match the name of a column from the Transactions table.

*Default*: `CallNumber`

### CleanUpVolumeSourceField

Specifies whether or not the Transaction's volume information should be removed from the specified VolumeSourceField. This is to help clean up transaction data in the event that the volume information was scraped from a webpage, where the volume information is conjoined with other data. The value of this setting is required and must be either "true" or "false".

*Default*: `false`

### VolumeDestinationField

Specifies the transaction field where the volume information for the transaction should be stored. The value of this setting is optional. If specified, the value of this setting must match the name of a column from the Transactions table.

*Default*: `ItemVolume`

### BarcodeDestinationField

Specifies the transaction field where gathered barcode information should be stored. The value of this setting is optional. If specified, the value of this setting must match the name of a column from the Transactions table.

*Default*: `ItemEdition`

### ReplaceVolumeWhenNotNull

Determines if the specified volume destination field is replaced if here is already set information in the field.

*Default*: `false`

### ExactSearch

Determines whether searching is exact (i.e., looks for an exact string match). If set to false, searching would rather rely on substring matching.

*Default*: `true`

### CallNumberFieldRegularExpression

A regular expression for parsing the call number field for volume information. If set to nothing, full string of field is used.

*Default*: `([B,b]ox\s*\d+)`

## Workflow Summary

The addon watches the transaction queue specified by the RequestMonitorQueue addon setting. When the addon detects that there are transactions present in the queue, it will grab bibId and volume information from the transaction. Using the bibId and volume information, the addon will attempt to download information regarding a single item using Sierra's API. If exactly one item is found, the item's information will be added to the transaction, which will then be routed to the specified success queue. If anything does not occur as expected during this process, a note will be added to the transaction, and it will be placed into the specified error queue.

## Error Handling

All error cases add a note to the transaction and then route the transaction to the specified error queue. From that queue, staff should be able to

1. process the request as normal,
2. manually fix the record and then route it back into monitor queue, or
3. manually adjust the addon's settings and then route affected transactions back into the monitor queue.

## Error Cases

The addon will route transactions into the error queue for any of the following reasons.

- BibID or Volume was not present in the specified fields of the transaction
- The connection to Sierra's API failed
- The API request failed
- The API request returned 0 results
- The API request returned more than 1 single result