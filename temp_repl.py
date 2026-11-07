import sys

path = 'd:/Courses/terraform-k8s-lab/ec2.tf'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Find old connection section
target = content.find('  # ===========================================================================\n  # CONNECTION')
print(f'Position to cut from: {target}')

if target < 0:
    print('ERROR: target not found')
    sys.exit(1)

# Read new section from stdin or use empty
print(f'Content length before: {len(content)}')
print(f'Saving up to position {target}')
with open(path + '.part', 'w', encoding='utf-8') as f:
    f.write(content[:target])
print(f'Wrote {target} bytes to .part file, now append the rest manually')
