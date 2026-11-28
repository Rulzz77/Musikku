package hub

import "testing"

func TestDetachDoesNotRemoveReplacementConnection(t *testing.T) {
	h := NewHub()
	oldConn := &SafeConn{}
	newConn := &SafeConn{}
	h.sockets["party"] = map[string]*SafeConn{"member": newConn}

	if h.Detach("party", "member", oldConn) {
		t.Fatal("detaching an old socket must not report that it removed the current connection")
	}
	if !h.HasConnection("party", "member") {
		t.Fatal("replacement connection was removed by stale detach")
	}

	if !h.Detach("party", "member", newConn) {
		t.Fatal("detaching the current socket should remove the member connection")
	}
	if h.HasConnection("party", "member") {
		t.Fatal("current connection should no longer be registered")
	}
}
