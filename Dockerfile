# Use the official Microsoft PowerShell Alpine image for a lightweight container
FROM mcr.microsoft.com/powershell:lts-alpine

# Set working directory inside the container
WORKDIR /app

# Copy the PowerShell script into the container
COPY Sync-AbsToBookOrbit.ps1 .

# Create the default volume mount point
RUN mkdir -p /media

# Set default environment variables
ENV MEDIA_ROOT=/media

# Run the sync script when the container starts
ENTRYPOINT ["pwsh", "-File", "/app/Sync-AbsToBookOrbit.ps1"]
