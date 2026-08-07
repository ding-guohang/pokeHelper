package httpapi

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
)

const maxJSONBody = 1 << 20

func decodeJSON(request *http.Request, destination any) error {
	decoder := json.NewDecoder(io.LimitReader(request.Body, maxJSONBody))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("httpapi: multiple JSON values")
		}
		return err
	}
	return nil
}

func writeJSON(response http.ResponseWriter, status int, value any) {
	body, err := json.Marshal(value)
	if err != nil {
		http.Error(response, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}
	response.Header().Set("Content-Type", "application/json")
	response.WriteHeader(status)
	_, _ = response.Write(body)
}
