import ballerina/http;
import ballerina/io;
import ballerina/data.jsondata;

configurable string claudeKey = ?;
configurable string anthropicVersion = ?;
configurable string model = ?;
configurable string anthropicEndpointUrl = ?;

isolated json[] messages = [];

public type Prompt record {
    string prompt;
};

service on new http:Listener(3000) {
    private final http:Client claudeEp;

    isolated function init() returns error? {
        self.claudeEp = check new (anthropicEndpointUrl);
    }

    isolated resource function post messages(Prompt prompt) returns stream<http:SseEvent, error?>|error {
        json[] msgs;
        lock {
            messages.push({role: "user", content: prompt.prompt});
            msgs = messages.clone();
        }
        io:println("USER: ", prompt.prompt);
        io:println("#############################################################################");
        json request = {
            model,
            system: "You are an expert assistant in generating ballerina code for a given usecase",
            'stream: true,
            messages: msgs,
            max_tokens: 1024
        };
        stream<http:SseEvent, error?> eventStream = check self.claudeEp->/messages.post(request, {"x-api-key": claudeKey, "anthropic-version": anthropicVersion});
        stream<http:SseEvent, error?> passThroughStream = new (new PassThroughStreamGen(eventStream));
        return passThroughStream;
    }
}

class PassThroughStreamGen {
    private final stream<http:SseEvent, error?> eventStream;
    private boolean isClosed = false;
    private final string[] tokens = [];

    isolated function init(stream<http:SseEvent, error?> eventStream) {
        self.eventStream = eventStream;
        io:print("ASSISTANT: ");
    }

    public isolated function next() returns record {|http:SseEvent value;|}|error? {
        if self.isClosed {
            return ();
        }
        record {|http:SseEvent value;|}? recordVal = check self.eventStream.next();
        if recordVal is () {
            self.isClosed = true;
            return ();
        }

        anydata data = recordVal.value.data;
        if data is string {
            json jsonData = check data.fromJsonString();
            json|error token = jsondata:read(jsonData, `$.delta.text`);
            if token is string {
                io:print(token);
                self.tokens.push(token);
            }
        }
        return recordVal;
    }

    public isolated function close() returns error? {
        io:println();
        io:println("#############################################################################");
        string content = string:'join("", ...self.tokens);
        lock {
            messages.push({role: "assistant", content});
        }
        self.isClosed = true;
    }
}
