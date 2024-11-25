package ajax

import (
	"database/sql"
	"net/http"
)

type Auth struct {
	UserID uint
	Role   string
}

type AjaxErrorPayload struct {
	ErrorCode string `json:"errorCode"`
}

// AjaxRouteAuthOptional represents an AJAX handler where authentication is optional,
// that returns a response object to be sent as JSON, and a status code.
type AjaxRouteAuthOptional func(
	db *sql.DB,
	auth *Auth,
	w http.ResponseWriter,
	r *http.Request,
) (interface{}, int)

// AjaxRouteAuthRequired represents an AJAX handler where authenticaition is mandatory,
// that returns a response object to be sent as JSON, and a status code.
type AjaxRouteAuthRequired func(
	db *sql.DB,
	auth Auth,
	w http.ResponseWriter,
	r *http.Request,
) (interface{}, int)
