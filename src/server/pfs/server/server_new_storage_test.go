package server

import (
	"archive/tar"
	"bytes"
	"io"
	"strconv"
	"strings"
	"testing"

	"github.com/pachyderm/pachyderm/src/client/pfs"
	"github.com/pachyderm/pachyderm/src/client/pkg/require"
)

func TestCompaction(t *testing.T) {
	config := GetBasicConfig()
	config.NewStorageLayer = true
	config.StorageMemoryThreshold = 20
	config.StorageShardThreshold = 20
	config.StorageLevelZeroSize = 10
	c := GetPachClient(t, config)
	repo := "test"
	branch := "master"
	require.NoError(t, c.CreateRepo(repo))
	var commit *pfs.Commit
	var err error
	for i := 0; i < 10; i++ {
		commit, err = c.StartCommit(repo, branch)
		require.NoError(t, err)
		buf := &bytes.Buffer{}
		tw := tar.NewWriter(buf)
		// Create files.
		for j := 0; j < 10; j++ {
			s := strconv.Itoa(i*10 + j)
			hdr := &tar.Header{
				Name: "/file" + s,
				Size: int64(len(s)),
			}
			require.NoError(t, tw.WriteHeader(hdr))
			_, err := io.Copy(tw, strings.NewReader(s))
			require.NoError(t, err)
			require.NoError(t, tw.Flush())
		}
		require.NoError(t, tw.Close())
		require.NoError(t, c.PutTar(repo, commit.ID, buf))
		require.NoError(t, c.FinishCommit(repo, commit.ID))
	}
	tarBuf := &bytes.Buffer{}
	getContent := func() string {
		contentBuf := &bytes.Buffer{}
		tr := tar.NewReader(tarBuf)
		_, err := tr.Next()
		require.NoError(t, err)
		_, err = io.Copy(contentBuf, tr)
		require.NoError(t, err)
		return contentBuf.String()
	}
	require.NoError(t, c.GetTar(repo, commit.ID, "/file0", tarBuf))
	require.Equal(t, "0", getContent())
	tarBuf.Reset()
	require.NoError(t, c.GetTar(repo, commit.ID, "/file50", tarBuf))
	require.Equal(t, "50", getContent())
	tarBuf.Reset()
	require.NoError(t, c.GetTar(repo, commit.ID, "/file99", tarBuf))
	require.Equal(t, "99", getContent())
}
