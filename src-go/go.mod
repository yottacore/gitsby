module github.com/yottacore/gitsby

go 1.26.2

// Since Go 1.23 EvalSymlinks leaves a junction as written, so a folder rule
// through one never matched (canonPath). The pair puts back the old reading: a
// junction resolves like a symlink, and a mounted volume by its drive letter.
godebug (
	winsymlink=0
	winreadlinkvolume=0
)

require (
	// Tests only: the SHCL 2.x writer, which makes files in the old format.
	github.com/jim-collier/shcl/source/go/v2 v2.0.0
	// Tests only: fails the run on a goroutine left running.
	go.uber.org/goleak v1.3.0
)

require github.com/yottacore/shcl/source/go/v3 v3.0.0-beta1
