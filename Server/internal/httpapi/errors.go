package httpapi

import "net/http"

type errorEnvelope struct {
	Error errorBody `json:"error"`
}

type errorBody struct {
	Code      string `json:"code"`
	RequestID string `json:"requestID"`
}

func writeTypedError(
	response http.ResponseWriter,
	status int,
	code string,
	requestID string,
) {
	writeJSON(response, status, errorEnvelope{
		Error: errorBody{Code: code, RequestID: requestID},
	})
}
