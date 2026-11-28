package protocol

import (
	"errors"
	"net/netip"
	"net/url"
	"strconv"
	"strings"
)

// Server -> Client frame types
const (
	FrameWelcome = "welcome"
	FrameState   = "state"
	FrameQueue   = "queue"
	FrameMembers = "members"
	FramePong    = "pong"
	FrameError   = "error"
	FrameBye     = "bye"
	FrameActivity = "activity"
)

// Client -> Server frame types
const (
	FramePing      = "ping"
	FrameControl   = "control"
	FrameSync      = "sync"
	FrameSyncQueue = "syncQueue"
	FrameReport    = "report"
)

// Control actions
const (
	ActionPlay        = "play"
	ActionPause       = "pause"
	ActionSeek        = "seek"
	ActionSetTrack    = "setTrack"
	ActionSetQueue    = "setQueue"
	ActionQueueAdd    = "queueAdd"
	ActionQueueRemove = "queueRemove"
	ActionQueueClear  = "queueClear"
	ActionQueueMove   = "queueMove"
	ActionNext        = "next"
	ActionPrevious    = "previous"
	ActionKick        = "kick"
	ActionSetMaxMembers = "setMaxMembers"
	ActionSetAutoplay = "setAutoplay"
	ActionSetHostOnlyControl = "setHostOnlyControl"
)

// ControlActions are the actions a party's HostOnlyControl setting restricts to
// the host. Membership actions are not here: kick and setMaxMembers are already
// host-only unconditionally, and setHostOnlyControl has to stay reachable by
// the host to be turned back off.
var ControlActions = map[string]bool{
	ActionPlay:        true,
	ActionPause:       true,
	ActionSeek:        true,
	ActionSetTrack:    true,
	ActionSetQueue:    true,
	ActionQueueAdd:    true,
	ActionQueueRemove: true,
	ActionQueueClear:  true,
	ActionQueueMove:   true,
	ActionNext:        true,
	ActionPrevious:    true,
	ActionSetAutoplay: true,
}


var nonPublicIPv4Ranges = []netip.Prefix{
	netip.MustParsePrefix("0.0.0.0/8"),
	netip.MustParsePrefix("100.64.0.0/10"),
	netip.MustParsePrefix("169.254.0.0/16"),
	netip.MustParsePrefix("192.0.0.0/24"),
	netip.MustParsePrefix("192.0.2.0/24"),
	netip.MustParsePrefix("192.88.99.0/24"),
	netip.MustParsePrefix("198.18.0.0/15"),
	netip.MustParsePrefix("198.51.100.0/24"),
	netip.MustParsePrefix("203.0.113.0/24"),
}

var nonPublicIPv6Ranges = []netip.Prefix{
	netip.MustParsePrefix("2001:db8::/32"),
}

// IsSafeRemoteHTTPURL accepts absolute HTTP(S) URLs suitable for displaying
// remote avatars and artwork. The server never fetches these URLs, but every
// participant's device may request them: local and special-use destinations
// are rejected to prevent remote members from targeting other devices' LANs.
func IsSafeRemoteHTTPURL(raw string) bool {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || parsed == nil || parsed.User != nil {
		return false
	}
	if !strings.EqualFold(parsed.Scheme, "http") && !strings.EqualFold(parsed.Scheme, "https") {
		return false
	}
	host := strings.TrimSuffix(strings.ToLower(parsed.Hostname()), ".")
	if host == "" {
		return false
	}
	if port := parsed.Port(); port != "" {
		value, err := strconv.Atoi(port)
		if err != nil || value < 1 || value > 65535 {
			return false
		}
	}
	if host == "localhost" || strings.HasSuffix(host, ".localhost") ||
		strings.HasSuffix(host, ".local") || strings.HasSuffix(host, ".lan") ||
		strings.HasSuffix(host, ".internal") || strings.HasSuffix(host, ".home") ||
		strings.HasSuffix(host, ".localdomain") {
		return false
	}
	if addr, err := netip.ParseAddr(host); err == nil {
		addr = addr.Unmap()
		if !addr.IsValid() || addr.IsPrivate() || addr.IsLoopback() ||
			addr.IsLinkLocalUnicast() || addr.IsLinkLocalMulticast() ||
			addr.IsMulticast() || addr.IsUnspecified() || !addr.IsGlobalUnicast() {
			return false
		}
		if addr.Is4() {
			for _, prefix := range nonPublicIPv4Ranges {
				if prefix.Contains(addr) {
					return false
				}
			}
		} else {
			for _, prefix := range nonPublicIPv6Ranges {
				if prefix.Contains(addr) {
					return false
				}
			}
		}
		return true
	}
	// Numeric host spellings such as 127.1 or 0x7f000001 are interpreted as
	// loopback by some URL stacks; only normal DNS names are accepted here.
	if !strings.Contains(host, ".") || isNumericHostname(host) {
		return false
	}
	return true
}

func isNumericHostname(host string) bool {
	hasDigit := false
	for _, r := range host {
		if r >= '0' && r <= '9' {
			hasDigit = true
			continue
		}
		if r != '.' && r != 'x' && r != 'X' &&
			!(r >= 'a' && r <= 'f') && !(r >= 'A' && r <= 'F') {
			return false
		}
	}
	return hasDigit
}

// JoinRequest is the identity submitted when creating or joining a party.
type JoinRequest struct {
	UserId      string  `json:"userId"`
	DeviceId    string  `json:"deviceId"`
	DisplayName string  `json:"displayName"`
	AvatarUrl   *string `json:"avatarUrl,omitempty"`
	MaxMembers  *int    `json:"maxMembers,omitempty"`
	AutoplayEnabled *bool `json:"autoplayEnabled,omitempty"`
}

// Validate ensures all required identity fields are present and safe.
func (r *JoinRequest) Validate() error {
	r.UserId = strings.TrimSpace(r.UserId)
	if r.UserId == "" || len(r.UserId) > 128 {
		return errors.New("userId must be between 1 and 128 characters")
	}

	r.DeviceId = strings.TrimSpace(r.DeviceId)
	if r.DeviceId == "" || len(r.DeviceId) > 128 {
		return errors.New("deviceId must be between 1 and 128 characters")
	}

	r.DisplayName = strings.TrimSpace(r.DisplayName)
	if r.DisplayName == "" || len(r.DisplayName) > 80 {
		return errors.New("displayName must be between 1 and 80 characters")
	}

	if r.AvatarUrl != nil {
		trimmed := strings.TrimSpace(*r.AvatarUrl)
		if trimmed == "" {
			r.AvatarUrl = nil
		} else if len(trimmed) > 1000 {
			return errors.New("avatarUrl must not exceed 1000 characters")
		} else if !IsSafeRemoteHTTPURL(trimmed) {
			return errors.New("avatarUrl must be a public http(s) URL")
		} else {
			r.AvatarUrl = &trimmed
		}
	}
	if r.MaxMembers != nil && (*r.MaxMembers < 2 || *r.MaxMembers > 10) {
		return errors.New("maxMembers must be between 2 and 10")
	}
	return nil
}
