# ---
# description: The manifest for distributing ruby via the Homebrew CLI. 
# ---

class Treedocs < Formula
  desc "Generate and maintain tree-style documentation for codebases"
  homepage "https://github.com/DandyLyons/treedocs"
  license "MIT"
  # Add a stable GitHub release archive URL and SHA256 in DandyLyons/homebrew-tap
  # after the first release tag exists.
  head "https://github.com/DandyLyons/treedocs.git", branch: "main"

  depends_on xcode: ["16.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    libexec.install ".build/release/treedocs", ".build/release/treedocs_treedocs.bundle"
    bin.write_exec_script libexec/"treedocs"
  end

  test do
    assert_path_exists libexec/"treedocs_treedocs.bundle"
    system bin/"treedocs", "init", "--non-interactive"
    assert_path_exists testpath/"treedocs.yaml"
    assert_match version.to_s, shell_output("#{bin}/treedocs --version") unless build.head?
  end
end
