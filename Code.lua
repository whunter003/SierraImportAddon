--[[
JsonParser.lua

Usage:

    The function ParseJSON (jsonString) accepts a
    string representation of a JSON object or array
    and returns the object or array as a Lua table
    with the same structure. Individual properties
    can be referenced using either the dot notation
    or the array notation.

Notes:

    All null values in the original JSON stream will
    be stored in the output table as JsonParser.NIL.
    This is a necessary convention, because Lua
    tables cannot store nil values and it may be
    desirable to have a stored null value versus
    not having the key present.

Requires:

    Newtonsoft.Json
--]]

luanet.load_assembly("System")
luanet.load_assembly("Newtonsoft.Json")
luanet.load_assembly("log4net")

JsonParser = {}
JsonParser.__index = JsonParser
JsonParser.NIL = {}

JsonParser.Types = {}
JsonParser.Types["StringReader"] = luanet.import_type("System.IO.StringReader")
JsonParser.Types["JsonToken"] = luanet.import_type("Newtonsoft.Json.JsonToken")
JsonParser.Types["JsonTextReader"] = luanet.import_type("Newtonsoft.Json.JsonTextReader")

JsonParser.rootLogger = "AtlasSystems.Addons.SierraServerAddon"
JsonParser.Log = luanet.import_type("log4net.LogManager").GetLogger(JsonParser.rootLogger)


function JsonParser:ParseJSON (jsonString)
    --[[
        Parses an input JSON string and outputs a
        lua table representation of the contained
        JSON data. JSON properties that contain
        null will be represented as JsonParser.NIL.

        Supports nested objects and arrays.
    ]]

    local stringReader = JsonParser.Types["StringReader"](jsonString)
    local reader = JsonParser.Types["JsonTextReader"](stringReader)

    local outputTable = ""

    if (reader:Read()) then
        if (reader.TokenType == JsonParser.Types["JsonToken"].StartObject) then
            outputTable = JsonParser:BuildFromJsonObject(reader)
        elseif (reader.TokenType == JsonParser.Types["JsonToken"].StartArray) then
            outputTable = JsonParser:BuildFromJsonArray(reader)
        elseif (jsonString == nil) then
            outputTable = ""
        else
            outputTable = jsonString
        end
    end

    return outputTable
end


function JsonParser:BuildFromJsonObject (reader)
    --[[
        Uses the provided JsonTextReader to build a lua table
        from a JSON object. Not meant to be called from outside
        this module.
    ]]

    local array = {}

    while (reader:Read()) do

        if (reader.TokenType == JsonParser.Types["JsonToken"].EndObject) then 
            return array
        end

        if (reader.TokenType == JsonParser.Types["JsonToken"].PropertyName) then
            local propertyName = reader.Value

            if (reader:Read()) then

                if (reader.TokenType == JsonParser.Types["JsonToken"].StartObject) then
                    array[propertyName] = JsonParser:BuildFromJsonObject(reader)
                elseif (reader.TokenType == JsonParser.Types["JsonToken"].StartArray) then
                    array[propertyName] = JsonParser:BuildFromJsonArray(reader)
                elseif (reader.Value == nil) then
                    array[propertyName] = JsonParser.NIL
                else
                    array[propertyName] = reader.Value
                end

            end
        end
    end

    return array
end


function JsonParser:BuildFromJsonArray (reader)
    --[[
        Uses the provided JsonTextReader to build a lua table
        from a JSON array. Not meant to be called from outside
        this module.
    ]]

    local array = {}

    while (reader:Read()) do

        if (reader.TokenType == JsonParser.Types["JsonToken"].EndArray) then
            return array    
        elseif (reader.TokenType == JsonParser.Types["JsonToken"].StartArray) then
            table.insert(array, JsonParser:BuildFromJsonArray(reader))
        elseif (reader.TokenType == JsonParser.Types["JsonToken"].StartObject) then
            table.insert(array, JsonParser:BuildFromJsonObject(reader))
        elseif (reader.Value == nil) then
            table.insert(array, JsonParser.NIL)
        else
            table.insert(array, reader.Value)
        end
    end

    return array
end

--[[
Utilities

Usage:
    This section contains useful functions for
    the rest of the solution

]]

Utility = {}
Utility.__index = Utility

function Utility.Trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

--[[
SierraApi.lua

Usage:

    This file contains the SierraApi class,
    which contains methods related to interacting
    with the Sierra V3 API.

Requires:

    Requires the Atlas Systems functionality: JsonParser.lua

]]


luanet.load_assembly("System")
luanet.load_assembly("log4net")


SierraApi = {}
SierraApi.__index = SierraApi


SierraApi.Types = {}
SierraApi.Types["Convert"] = luanet.import_type("System.Convert")
SierraApi.Types["Encoding"] = luanet.import_type("System.Text.Encoding")
SierraApi.Types["WebClient"] = luanet.import_type("System.Net.WebClient")
SierraApi.Types["NameValueCollection"] = luanet.import_type("System.Collections.Specialized.NameValueCollection")
SierraApi.Types["System.Type"] = luanet.import_type("System.Type")
SierraApi.Types["StreamReader"] = luanet.import_type("System.IO.StreamReader");


SierraApi.UrlSuffixes = {}
SierraApi.UrlSuffixes.Token = "/token"
SierraApi.UrlSuffixes.ItemsQueryItemFields = "?fields=default,fixedFields,varFields"
SierraApi.UrlSuffixes.ItemsBibIds = "/items?bibIds=%s&fields=default,fixedFields,varFields"


SierraApi.ApiEndpoints = {
    --[[
        Enumeration for determining
        the API that was used when
        formatting error messages.

        API endpoints that are not
        yet needed have not been
        added.
    ]]

    info       = 0,
    items      = 1,
    itemsQuery = 2
}


SierraApi.rootLogger = "AtlasSystems.Addons.SierraServerAddon"
SierraApi.Log = luanet.import_type("log4net.LogManager").GetLogger(SierraApi.rootLogger)


function SierraApi:Create(apiUrl, userAgent)
    --[[
        Initializes a SierraApi object.
    ]]

    if (not type(apiUrl) == "string") or apiUrl == "" then
        error({ Message = "Cannot initialize Sierra API web client without an API URL." })
    end

    SierraApi.Log:DebugFormat("Initializing SierraApi Client with URL: {0}", apiUrl)

    local sierraApi = {}
    setmetatable(sierraApi, SierraApi)

    -- Strips off the last / if one is present
    if (string.sub(apiUrl, -1) == "/") then 
        apiUrl = string.sub(apiUrl, 1, -2)
    end

    sierraApi.ApiUrl = apiUrl
    sierraApi.AccessToken = ""
    sierraApi.UserAgent = userAgent or false

    return sierraApi
end


function SierraApi:UpdateAccessToken(clientKey, clientSecret)
    --[[
        Retrieves and stores the access_token
        under self.AccessToken. Also returns
        the access_token.
    ]]

    local accessToken = self:GetAccessToken(clientKey, clientSecret)
    SierraApi.Log:DebugFormat("Updated Access Token: {0}", accessToken)
    self.AccessToken = accessToken
    return accessToken
end


function SierraApi:GetAccessToken (clientKey, clientSecret)
    --[[
        Returns only the access_token from the 
        /token API response.
    ]]

    return self:GetAccessTokenResponse(clientKey, clientSecret).access_token
end


function SierraApi:GetAccessTokenResponse (clientKey, clientSecret)
    --[[
        Parses the JSON response from the Sierra 
        /token API and returns the response as a
        Lua table.

        Output:
        {
            access_token = <string>,
            token_type = <string>,
            expires_in = <int>
        }
    ]]

    if (not type(clientKey) == "string") or clientKey == "" then
        error({ Message = "Client Key must be a non-empty string." })

    elseif (not type(clientSecret) == "string") or clientSecret == "" then
        error({ Message = "Client Secret must be a non-empty string." })

    end


    SierraApi.Log:Info("Getting Client Credentials")

    local credentialWebClient = SierraApi.Types["WebClient"]()
    local encodedKeyAndSecret = SierraApi:Base64Encode(
        string.format("%s:%s", clientKey, clientSecret)
    )
    local authTokenUrl = self.ApiUrl .. SierraApi.UrlSuffixes.Token
    local uploadMethod = "POST"
    local uploadBody = "grant_type=client_credentials"

    credentialWebClient.Headers:Clear()
    credentialWebClient.Headers:Add("Authorization", "Basic " .. encodedKeyAndSecret)
    credentialWebClient.Headers:Add("Content-Type", "application/x-www-form-urlencoded")


    local authUploadSuccess, authUploadResult = pcall(function()
        SierraApi.Log:DebugFormat("Encoded Client Key and Secret: {0}", encodedKeyAndSecret)
        SierraApi.Log:DebugFormat("Posting to URL: {0}", authTokenUrl)
        return credentialWebClient:UploadString(authTokenUrl, uploadMethod, uploadBody)
    end)


    if (not authUploadSuccess) then
        SierraApi.Log:Warn("Failure occurred while obtaining access token.")
        error(authUploadResult)
    else
        SierraApi.Log:DebugFormat("Access Token Response: {0}", authUploadResult)
    end


    local parsedAuthResult = JsonParser:ParseJSON(authUploadResult)

    if parsedAuthResult.code and not parsedAuthResult.access_token then

        local message = "Bad authorization result returned from Sierra authorization."

        SierraApi.Log:Warn(message)

        if parsedAuthResult.name then
            SierraApi.Log:WarnFormat("Auth Response Name: {0}", parsedAuthResult.name)
            message = message .. string.format(" (Name: %s)", parsedAuthResult.name)
        end

        if parsedAuthResult.description then
            SierraApi.Log:WarnFormat("Auth Response Desc: {0}", parsedAuthResult.description)
            message = message .. string.format(" (Description: %s)", parsedAuthResult.description)
        end

        error({ Code = parsedAuthResult.code or -1, Message = message })
    end

    return parsedAuthResult 
end

function SierraApi:GetItems (bibId, volume, exact)
    --[[
        Uses Sierra's /items API to get all of
        the items that match the specified bibId
        and volume.

        Requires a bibId, and a volume.

        exact is a boolean value that will determine whether
        or not to match the string exactly.

        Note:
            This method will check each item that was
            returned for the specified bibId to see if
            that item has a volume and if the volume is
            1) a substring of the given volume if exact
            is false to support sites that have volume
            information concatenated with other information,
            or 2) an exact trimmed string.
    ]]

    if (not type(bibId) == "string") or bibId == "" then
        error({ Message = "bibId must be a non-empty string" })

    elseif (not type(volume) == "string") or volume == "" then
        error({ Message = "volume must be a non-empty string" })

    end

    SierraApi.Log:Info("Getting Items using Sierra Items API")
    SierraApi.Log:DebugFormat("Item bibId : \"{0}\"", bibId)
    SierraApi.Log:DebugFormat("Item volume: \"{0}\"", volume)

    local queryUrl = self.ApiUrl .. string.format(SierraApi.UrlSuffixes.ItemsBibIds, bibId)

    SierraApi.Log:DebugFormat("Getting item data using API url: {0}", queryUrl)

    local querySucceeded, queryResult = pcall(function()
        local webClient = self:BuildItemsWebClient()
        return webClient:DownloadString(queryUrl)
    end)

    if not querySucceeded then
        SierraApi.Log:ErrorFormat("Unsuccessful Items API call using url: {0}", queryUrl)
        SierraApi:HandleUploadError(queryResult, SierraApi.ApiEndpoints.items)
    end

    SierraApi.Log:DebugFormat("Sierra Items API Response: {0}", queryResult)
    local matchingItems = {}
    local parsedResult = JsonParser:ParseJSON(queryResult)

    for i_entry, v_entry in ipairs(parsedResult.entries or {}) do
        -- i_entry == index
        -- v_entry == value

        local entryId = v_entry.id or ""
        local v_volume = SierraApi:GetVarFieldValue(v_entry, "v")

        if v_volume and v_volume ~= "" then
            if exact then
                if Utility.Trim(volume) == Utility.Trim(v_volume) then
                    SierraApi.Log:DebugFormat("Sierra item record \"{0}\" matches specified bibId and volume (exact).", entryId)
                    table.insert(matchingItems, v_entry)
                end
            else
                if string.find(volume, v_volume, 1, true) then
                    SierraApi.Log:DebugFormat("Sierra item record \"{0}\" matches specified bibId and volume (substring).", entryId)
                    table.insert(matchingItems, v_entry)
                end
            end
        end
    end

    if table.getn(matchingItems) <= 0 then
        SierraApi.Log:Warn("No Sierra item records were found for the specified bibId and volume.")
    end

    return matchingItems
end

function SierraApi:GetVarFieldValue (itemRecord, varField, subField)
    --[[
        Gets the value of a particular varField
        from a particular item record. Can grab
        the varField's subField if a subField tag
        is supplied and is present in the item
        record.

        subField is not required.

        Returns single values.

        Returns nil if no content is found for the
        supplied query information.
    ]]

    if not type(varField) == "string" then
        error({ Message = "varField argument must be a string" })

    elseif not itemRecord then
        error({ Message = "Sierra item record cannot be nil or false" })

    elseif not itemRecord.varFields then
        error({ Message =  "Sierra item record does not contain varFields" })

    end


    local itemRecordId = itemRecord.id or ""


    for i_vf, v_varField in ipairs(itemRecord.varFields or {}) do
        if v_varField and v_varField.fieldTag == varField then

            if subField and subField ~= "" then

                for i_sf, v_subField in ipairs(v_varField.subFields or {}) do

                    if v_subField and v_subField.tag == subField then

                        if v_subField.content then
                            local content = v_subField.content
                            SierraApi.Log:DebugFormat(
                                "Sierra item record \"{0}\" varField \"{1}\" subField \"{2}\" contains \"{3}\".",
                                itemRecordId, varField, subField, content)
                            return content
                        else
                            SierraApi.Log:WarnFormat(
                                "Sierra item record \"{0}\" varField \"{1}\" subField \"{2}\" has no \"content\" property.", 
                                itemRecordId, varField, subField)
                            return nil
                        end
                    end
                end

                SierraApi.Log:WarnFormat(
                    "Sierra item record \"{0}\" varField \"{1}\" has no subFields with tag \"{2}\".",
                    itemRecordId, varField, subField)
                return nil
            end

            if v_varField.content then
                local content = v_varField.content
                SierraApi.Log:DebugFormat(
                    "Sierra item record \"{0}\" varField \"{1}\" contains \"{2}\".",
                    itemRecordId, varField, content)
                return content
            else
                SierraApi.Log:WarnFormat(
                    "Sierra item record \"{0}\" varField \"{1}\" has no \"content\" property.", 
                    itemRecordId, varField)
                return nil
            end
        end
    end

    SierraApi.Log:DebugFormat(
        "Sierra item record \"{0}\" does not contain varField \"{1}\"", 
        itemRecordId, varField)
    return nil
end


function SierraApi:GetVarFieldMarcData (itemRecord, varField)
    --[[
        Gets the marcTag, ind1, and ind2 values from
        a varField, if available. Returns the results
        as a table:

        {
            marcTag = "100",
            ind1 = "1",
            ind2 = " "
        }

        If a value is not available, the output table
        will store nil as the value, which will cause
        the key to not be present in the output.

        If the varField cannot be found, nil will be
        returned instead of a table.
    ]]

    if not type(varField) == "string" then
        error({ Message = "varField argument must be a string" })

    elseif not itemRecord then
        error({ Message = "Item record cannot be nil or false." })

    elseif not itemRecord.varFields then
        error({ Message = "Item record does not contain varFields" })

    end


    local itemRecordId = itemRecord.id or ""

    for i_vf, v_varField in ipairs(itemRecord.varFields or {}) do
        if v_varField and v_varField.fieldTag == varField then

            SierraApi.Log:DebugFormat(
                "Found varField \"{0}\" for item record \"{1}\". Returning its MARC data.",
                varField, itemRecordId)

            return {
                marcTag = v_varField.marcTag,
                ind1 = v_varField.ind1,
                ind2 = v_varField.ind2
            }
        end
    end

    SierraApi.Log:DebugFormat(
        "Could not find varField \"{0}\" under item record \"{1}\".",
        varField, itemRecordId)

    return nil
end


function SierraApi:GetFixedField (itemRecord, fixedField)
    --[[
        Gets a particular fixedField from a particular item
        record. Returns nil if no matching fixedField is
        found for the specified fixedField identifier.

        Fixed fields contain a few properties, so the
        output will be returned as a table. Below is
        an example of the output data format. The
        display property is not always available.

        {
            label = "LANG",
            value = "eng",
            display = "English"
        }
    ]]

    if not type(fixedField) == "string" then 
        error({ Message = "fixedField argument must be a string" })

    elseif not itemRecord then
        error({ Message = "Item record argument must be initialized" })

    elseif not itemRecord.fixedFields then
        error({ Message = "Item record does not contain fixedFields" })

    end


    if not itemRecord.fixedFields[fixedField] then
        SierraApi.Log:WarnFormat(
            "Item Record \"{0}\" does not contain fixedField \"{1}\"",
            itemRecord.id,
            fixedField)
        return nil
    end

    return itemRecord.fixedFields[fixedField]
end


function SierraApi:BuildItemsWebClient ()
    --[[
        Builds a WebClient that has headers which are needed
        for the items API of the Sierra API.
    ]]

    if not (type(self.AccessToken) == "string") or self.AccessToken == "" then
        error({ Message = "Cannot create Sierra API Web Client. Access token is blank." })
    end

    local webClient = SierraApi.Types["WebClient"]()
    webClient.Headers:Clear()
    webClient.Headers:Add("Authorization", "Bearer " .. self.AccessToken)

    if self.UserAgent and self.UserAgent ~= "" then
        webClient.Headers:Add("User-Agent", self.UserAgent)
    end

    return webClient
end


function SierraApi:HandleUploadError (returnedError, apiEndpoint)
    --[[
        Handles errors and exceptions that were

        apiEndpoint is a required parameter that determines
        which error handler to use.
    ]]

    if not returnedError then
        error({ Message = "returnedError cannot be null or false." })

    elseif SierraApi:IsType(returnedError, "LuaInterface.LuaScriptException") and returnedError.InnerException and SierraApi:IsType(returnedError.InnerException, "System.Net.WebException") then

		SierraApi.Log:Debug("Handling error encountered when receiving API response")
		SierraApi.Log:Debug("HTTP Error: " .. returnedError.InnerException.Message)

        if returnedError.InnerException.Response then
            SierraApi.Log:Debug("Attempting to parse response error from Sierra API.")

            local webExceptionResponse = returnedError.InnerException.Response
			local responseStream = webExceptionResponse:GetResponseStream();

			if responseStream then
				local responseStreamReader = SierraApi.Types["StreamReader"](responseStream)
				if responseStreamReader then
					local responseString = responseStreamReader:ReadToEnd();
					if responseString then
                        SierraApi.Log:DebugFormat("Response: {0}", responseString)

                        local errorMessageOpener = "A call to the Sierra API returned an error."

                        if apiEndpoint == SierraApi.ApiEndpoints.info then
                            errorMessageOpener = "A call to the Sierra /info API returned an error."

                        elseif apiEndpoint == SierraApi.ApiEndpoints.items then
                            errorMessageOpener = "A call to the Sierra /items API returned an error."
                        end

                        SierraApi:HandleSierraApiError(errorMessageOpener, responseString)
                    end
                end
            end
        end

        -- If the parsing of the response failed:
        returnedError = returnedError.InnerException

    elseif SierraApi:IsType(returnedError, "LuaInterface.LuaScriptException") and returnedError.InnerException and SierraApi:IsType(returnedError.InnerException, "System.Net.Sockets.SocketException") then

        SierraApi.Log:Debug("Handling error encountered with web socket")
		SierraApi.Log:Debug("HTTP Error: " .. returnedError.InnerException.Message)

        returnedError = returnedError.InnerException

    elseif type(returnedError) == "string" and returnedError ~= "" then
        returnedError = { Message = returnedError }

    elseif not returnedError.Message then
        returnedError.Message = "A .NET exception occurred while interacting with the Sierra API." 

    end

    error(returnedError)
end


function SierraApi:HandleSierraApiError (errorMessageOpener, infoResponse)
    --[[
        Formats and raises an error based on a
        bad response from Sierra's info API.

        The error message opener should be a short
        summary of the error, including the name of
        the API endpoint that raised the error. 
    ]]

    if type(infoResponse) == "string" then
        infoResponse = JsonParser:ParseJSON(infoResponse)
    end

    local message = errorMessageOpener

    if infoResponse.httpStatus then
        message = message .. string.format(" (HTTP Status: %s)", infoResponse.httpStatus)
    end

    if infoResponse.code then
        message = message .. string.format(" (Error Code: %d)", infoResponse.code)
    end

    if infoResponse.name then
        message = message .. string.format(" (Error Message: %s)", infoResponse.name)
    end

    if infoResponse.description then
        message = message .. string.format(" (Error Description: %s)", infoResponse.description)
    end

    SierraApi.Log:DebugFormat("Generated error message: {0}", message)
    error({ Code = infoResponse.code, Message = message })
end


function SierraApi:Base64Encode (plainText)
    --[[
        Encodes the input text in base64.
    ]]

    if not type(plainText) == "string" then
        error({ Message = "plainText argument must be a string." })
    end

    local textUTF8 = SierraApi.Types["Encoding"].UTF8:GetBytes(plainText)
    local textBase64 = SierraApi.Types["Convert"].ToBase64String(textUTF8)
    return textBase64
end


function SierraApi:IsType (o, t)
    --[[
        Determines if the specified object "o" is of 
        .NET type "t". t should be a string of the full 
        name of the .NET type, such as "System.DateTime"
    ]] 

    if ((o and type(o) == "userdata") and (t and type(t) == "string")) then
        local comparisonType = SierraApi.Types["System.Type"].GetType(t)

        SierraApi.Log:Debug(o:GetType().FullName)

        if (comparisonType) then
            -- The comparison type was successfully loaded so we can do a check
            -- that the object can be assigned to the comparison type.
            return comparisonType:IsAssignableFrom(o:GetType()), true
        else
            -- The comparison type was could not be loaded so we can only check
            -- based on the names of the types.
            return (o:GetType().FullName == t), false
        end
    end

    return false, false
end

-- =========================================================
-- Load settings and .NET Assemblies
-- =========================================================


local Settings = {}
Settings.RequestMonitorQueue = GetSetting("RequestMonitorQueue")
Settings.SuccessRouteQueue = GetSetting("SuccessRouteQueue")
Settings.ErrorRouteQueue = GetSetting("ErrorRouteQueue")

Settings.SierraApiUrl = GetSetting("SierraApiUrl")
Settings.ClientKey = GetSetting("ClientKey")
Settings.ClientSecret = GetSetting("ClientSecret")
Settings.UserAgent = GetSetting("UserAgent")

Settings.BibIdSourceField = GetSetting("BibIdSourceField")
Settings.VolumeSourceField = GetSetting("VolumeSourceField")
Settings.CleanUpVolumeSourceField = GetSetting("CleanUpVolumeSourceField")

Settings.VolumeDestinationField = GetSetting("VolumeDestinationField")
Settings.BarcodeDestinationField = GetSetting("BarcodeDestinationField")

Settings.VolumeSourceFieldRegularExpression = GetSetting("VolumeSourceFieldRegularExpression")
Settings.ExactSearch = GetSetting("ExactSearch")
Settings.ReplaceVolumeWhenNotNull = GetSetting("ReplaceVolumeWhenNotNull")


luanet.load_assembly("System")
luanet.load_assembly("log4net")
luanet.load_assembly("Mscorlib")


local Types = {}
Types["System.Type"] = luanet.import_type("System.Type")
Types["WebClient"] = luanet.import_type("System.Net.WebClient")
Types["StreamReader"] = luanet.import_type("System.IO.StreamReader")
Types["NameValueCollection"] = luanet.import_type("System.Collections.Specialized.NameValueCollection")
Types["Encoding"] = luanet.import_type("System.Text.Encoding")
Types["LogManager"] = luanet.import_type("log4net.LogManager")
Types["Regex"] = luanet.import_type("System.Text.RegularExpressions.Regex")


-- =========================================================
-- Main
-- =========================================================


local isCurrentlyProcessing = false
local sierraApi = nil


local Log = Types["LogManager"].GetLogger(JsonParser.rootLogger)


function Init ()
    RegisterSystemEventHandler("SystemTimerElapsed", "TimerElapsed")
end


function TimerElapsed (eventArgs)
    --[[
        Function that is called whenever the
        system manager triggers server addon
        execution.
    ]]

    if (not isCurrentlyProcessing) then
        isCurrentlyProcessing = true

        Log:Debug("Addon Settings: ")
        for settingKey, settingValue in pairs(Settings) do
            Log:DebugFormat("{0}: {1}", settingKey, settingValue)
        end

        local successfulAddonExecution, error = pcall(function()
            local successfulAddonExecution, error = pcall(function()
                if not sierraApi then
                    sierraApi = SierraApi:Create(Settings.SierraApiUrl)
                end

                local accessToken = sierraApi:UpdateAccessToken(Settings.ClientKey, Settings.ClientSecret)
                Log:DebugFormat("Generated Access Token: {0}", accessToken)

                ProcessDataContexts("TransactionStatus", Settings.RequestMonitorQueue, "HandleRequests")
            end)

            if not successfulAddonExecution then
                SierraApi:HandleUploadError(error, SierraApi.ApiEndpoints.info)
            end
        end)

        if not successfulAddonExecution then
            Log:Error("Unsuccessful addon execution.")
            Log:Error(error.Message or error)
        end

        isCurrentlyProcessing = false
    else
        Log:Debug("Addon is still executing.")
    end
end


-- =========================================================
-- ProcessDataContext functionality
-- =========================================================


function HandleRequests ()
    --[[
        Must be called from a ProcessDataContexts function.
        Runs for every transaction that meets the criteria specified
        by the ProcessDataContexts function.
    ]]

    local tn = GetFieldValue("Transaction", "TransactionNumber")
    Log:DebugFormat("Found transaction number {0} in \"{1}\"", tn, Settings.RequestMonitorQueue)

    local regex
    if Settings.VolumeSourceFieldRegularExpressionn and Settings.VolumeSourceFieldRegularExpression ~= "" then
        regex = Types["Regex"](Settings.VolumeSourceFieldRegularExpression)
        Log:DebugFormat("Found Regex \"{0}\" for VolumeSourceField.", Settings.VolumeSourceFieldRegularExpression)
    else
        Log:Debug("No Regex found.")
    end

    local success, result = pcall(
        function()
            local fieldFetchSuccess, transactionBibId, transactionVolume = pcall(
                function()
                    Log:DebugFormat("Getting BibID from transaction.{0}", Settings.BibIdSourceField)
                    local transactionBibId = GetFieldValue("Transaction", Settings.BibIdSourceField)
                    transactionBibId = transactionBibId:gsub("%D", "")
                    local transactionVolume
                    if regex ~= nil then
                        match = regex:Match(GetFieldValue("Transaction", Settings.VolumeSourceField))
                            if match.Success then
                                Log:DebugFormat("Using Regex for volume source field {0} results in match \"{1}\"",
                                    Settings.VolumeSourceField, match.Value)
                                transactionVolume = match.Value
                            end
                    else
                        Log:DebugFormat("Getting volume source field {1}", Settings.VolumeSourceField)
                        transactionVolume = GetFieldValue("Transaction", Settings.VolumeSourceField)
                    end
                    return transactionBibId, transactionVolume
                end
            )

            if not(fieldFetchSuccess) then
                Log:ErrorFormat("Error fetching BibID and Volume fields from Transaction {0}.", tn)
                error({ Message = "Error fetching BibID and Volume fields from the Transactions table." })
            end

            Log:DebugFormat("BibID : {0}", transactionBibId)
            Log:DebugFormat("Volume: {0}", transactionVolume)
            Log:Info("Searching for Sierra records.")

            local sierraRecords = sierraApi:GetItems(transactionBibId, transactionVolume, Settings.ExactSearch)
            local numRecords = table.getn(sierraRecords)

            if numRecords <= 0 then
                error({ Message = "No Sierra records were returned for the specified bibId and volume" })
            elseif numRecords > 1 then
                error({ Message = "Too many Sierra records were returned for the specified bibId and volume" })
            end


            local _, sierraRecord = next(sierraRecords, nil)
            local sierraRecordVolume = SierraApi:GetVarFieldValue(sierraRecord, "v")

            if Settings.CleanUpVolumeSourceField then
                local volStartIndex, volEndIndex = 
                    transactionVolume:find(sierraRecordVolume, 1, true)

                local nextTransactionVol = 
                    transactionVolume:sub(1, volStartIndex - 1) ..
                    transactionVolume:sub(volEndIndex + 1)

                Log:DebugFormat(
                    "Cleaning up VolumeSourceField. (Before: \"{0}\") (After: \"{1}\")",
                    transactionVolume,
                    nextTransactionVol)

                SetFieldValue("Transaction", Settings.VolumeSourceField, nextTransactionVol);
                SaveDataSource("Transaction")
            end

            if Settings.VolumeDestinationField and Settings.VolumeDestinationField ~= "" then
                local currentVolumeDestinationField = GetFieldValue("Transaction", Settings.VolumeDestinationField)
                if (Settings.ReplaceVolumeWhenNotNull or (not currentVolumeDestinationField) or currentVolumeDestinationField == "") then
                    Log:Debug("Populating volume destination field")
                    SetFieldValue("Transaction", Settings.VolumeDestinationField, sierraRecordVolume)
                    SaveDataSource("Transaction")
                end
            end

            if Settings.BarcodeDestinationField and Settings.BarcodeDestinationField ~= "" then
                Log:Debug("Populating barcode destination field")

                if (not type(sierraRecord.barcode) == "string") or sierraRecord.barcode == "" then
                    error({ Message = "Cannot populate barcode from Sierra. Barcode is either missing or blank." })
                end

                SetFieldValue("Transaction", Settings.BarcodeDestinationField, sierraRecord.barcode)
                SaveDataSource("Transaction")
            end

            return nil
        end
    )

    if success then
        Log:InfoFormat("Addon successfully populated Transaction {0} with data from Sierra", tn)
        ExecuteCommand("Route", { tn, Settings.SuccessRouteQueue })

    else
        Log:ErrorFormat("Failed to populate transaction {0} with data from Sierra. Routing transaction to \"{1}\".", tn, Settings.ErrorRouteQueue)
        Log:Error(result.Message or result)
        ExecuteCommand("AddNote", { tn, result.Message or result })
        ExecuteCommand("Route", { tn, Settings.ErrorRouteQueue })

    end
end