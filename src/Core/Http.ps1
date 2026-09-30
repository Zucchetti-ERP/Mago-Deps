function Test-HttpEndpoint {
    param([string]$Url, [int[]]$OkCodes = @(200))
    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        $code = [int]$resp.StatusCode
        return @{ Code = $code; Ok = ($code -in $OkCodes) }
    } catch {
        $inner = $_.Exception
        if ($inner.InnerException) { $inner = $inner.InnerException }
        if ($inner -is [System.Net.WebException] -and $null -ne $inner.Response) {
            $code = [int]$inner.Response.StatusCode
            return @{ Code = $code; Ok = ($code -in $OkCodes) }
        }
        return @{ Code = -1; Ok = $false }
    }
}
