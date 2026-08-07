package password

import (
	"bufio"
	"fmt"
	"io"
	"strings"

	"golang.org/x/text/cases"
	"golang.org/x/text/unicode/norm"
)

type Blocklist struct {
	entries map[string]struct{}
}

func ParseBlocklist(reader io.Reader) (Blocklist, error) {
	entries := make(map[string]struct{})
	scanner := bufio.NewScanner(reader)
	for scanner.Scan() {
		value := strings.TrimSpace(scanner.Text())
		if value == "" || strings.HasPrefix(value, "#") {
			continue
		}
		entries[blocklistKey(value)] = struct{}{}
	}
	if err := scanner.Err(); err != nil {
		return Blocklist{}, fmt.Errorf("read password blocklist: %w", err)
	}
	return Blocklist{entries: entries}, nil
}

func (b Blocklist) Contains(value string) bool {
	_, found := b.entries[blocklistKey(value)]
	return found
}

func blocklistKey(value string) string {
	return norm.NFC.String(cases.Fold().String(norm.NFC.String(value)))
}
