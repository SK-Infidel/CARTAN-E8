$token_path = "$env:USERPROFILE\.cache\huggingface\token"
if (Test-Path $token_path) {
    $token = (Get-Content $token_path -Raw).Trim()
    Write-Host "Authenticated HuggingFace Token Loaded."
    curl.exe -L -H "Authorization: Bearer $token" "https://huggingface.co/google/gemma-4-E4B-it/resolve/main/model.safetensors" -o "cache_google_gemma-4-E4B-it_model.safetensors"
} else {
    Write-Host "No HF token found at $token_path"
    curl.exe -L "https://huggingface.co/google/gemma-4-E4B-it/resolve/main/model.safetensors" -o "cache_google_gemma-4-E4B-it_model.safetensors"
}
